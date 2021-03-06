#!/bin/bash

## prepare configuration

IS_COMPONENT_BUILD=true
IS_LINUX=false
SNAPSHOT_PREFIX=""

case "$(uname -s)" in

   Darwin)
	 echo 'Mac OS X'
		 IS_COMPONENT_BUILD=false
		 cp ./llvm-ar ./v8/third_party/llvm-build/Release+Asserts/bin
		 NDK_BUILD_TOOLS_ARR=(
				$ANDROID_NDK_HOME/toolchains/arm-linux-androideabi-4.9/prebuilt/darwin-x86_64/arm-linux-androideabi/bin \
				$ANDROID_NDK_HOME/toolchains/aarch64-linux-android-4.9/prebuilt/darwin-x86_64/aarch64-linux-android/bin \
				$ANDROID_NDK_HOME/toolchains/x86-4.9/prebuilt/darwin-x86_64/i686-linux-android/bin \
				$ANDROID_NDK_HOME/toolchains/x86_64-4.9/prebuilt/darwin-x86_64/x86_64-linux-android/bin
		)
	 ;;

   Linux)
	 echo 'Linux'
		 IS_LINUX=true
		 SNAPSHOT_PREFIX="snapshot-"
		 NDK_BUILD_TOOLS_ARR=($ANDROID_NDK_HOME/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/arm-linux-androideabi/bin \
				$ANDROID_NDK_HOME/toolchains/aarch64-linux-android-4.9/prebuilt/linux-x86_64/aarch64-linux-android/bin \
				$ANDROID_NDK_HOME/toolchains/x86-4.9/prebuilt/linux-x86_64/i686-linux-android/bin \
				$ANDROID_NDK_HOME/toolchains/x86_64-4.9/prebuilt/linux-x86_64/x86_64-linux-android/bin)
	 ;;

   *)
	 echo 'Unsupported OS'
	 ;;
esac

# The order of CPU architectures in this array must be the same
# as the order of NDK tools in the NDK_BUILD_TOOLS_ARR array
ARCH_ARR=(arm arm64 x86)

BUILD_DIR_PREFIX="outgn"

BUILD_TYPE="release"

cd v8
if [[ $1 == "debug" ]] ;then
		BUILD_TYPE="debug"
fi
# generate project in release mode
for CURRENT_ARCH in ${ARCH_ARR[@]}
do
		ARGS=
		if [[ $BUILD_TYPE == "debug" ]] ;then
				gn gen $BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE --args="is_component_build=$IS_COMPONENT_BUILD v8_use_snapshot=true v8_use_external_startup_data=true v8_enable_embedded_builtins=true is_debug=true symbol_level=2 target_cpu=\"$CURRENT_ARCH\" v8_target_cpu=\"$CURRENT_ARCH\" v8_enable_i18n_support=false target_os=\"android\" v8_android_log_stdout=false"
				if $IS_LINUX; then
					gn gen $BUILD_DIR_PREFIX/$SNAPSHOT_PREFIX$CURRENT_ARCH-$BUILD_TYPE --args="is_component_build=false v8_use_snapshot=true v8_use_external_startup_data=true v8_enable_embedded_builtins=true is_debug=true symbol_level=2 target_cpu=\"$CURRENT_ARCH\" v8_target_cpu=\"$CURRENT_ARCH\" v8_enable_i18n_support=false target_os=\"android\" v8_android_log_stdout=false"
				fi
		else
				gn gen $BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE --args="is_component_build=$IS_COMPONENT_BUILD v8_use_snapshot=true v8_use_external_startup_data=true v8_enable_embedded_builtins=true is_official_build=true use_thin_lto=false is_debug=false symbol_level=0 target_cpu=\"$CURRENT_ARCH\" v8_target_cpu=\"$CURRENT_ARCH\" v8_enable_i18n_support=false target_os=\"android\" v8_android_log_stdout=false"
				if $IS_LINUX; then
					gn gen $BUILD_DIR_PREFIX/$SNAPSHOT_PREFIX$CURRENT_ARCH-$BUILD_TYPE --args="is_component_build=false v8_use_snapshot=true v8_use_external_startup_data=true v8_enable_embedded_builtins=true is_official_build=true use_thin_lto=false is_debug=false symbol_level=0 target_cpu=\"$CURRENT_ARCH\" v8_target_cpu=\"$CURRENT_ARCH\" v8_enable_i18n_support=false target_os=\"android\" v8_android_log_stdout=false"
				fi
		fi
done

# compile project
COUNT=0
for CURRENT_ARCH in ${ARCH_ARR[@]}
do
		# make fat build
		V8_FOLDERS=(v8_base v8_libplatform v8_libbase v8_libsampler v8_external_snapshot v8_initializers v8_init)

		SECONDS=0
		ninja -C $BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE ${V8_FOLDERS[@]} inspector
		if $IS_LINUX; then
			ninja -C $BUILD_DIR_PREFIX/$SNAPSHOT_PREFIX$CURRENT_ARCH-$BUILD_TYPE run_mksnapshot_default
		fi
		echo "build finished in $SECONDS seconds"

		DIST="./dist/"
		mkdir -p $DIST/$CURRENT_ARCH-$BUILD_TYPE

		CURRENT_BUILD_TOOL=${NDK_BUILD_TOOLS_ARR[$COUNT]}
		COUNT=$COUNT+1
		V8_FOLDERS_LEN=${#V8_FOLDERS[@]}
		for CURRENT_V8_FOLDER in ${V8_FOLDERS[@]}
		do
				LAST_PARAM=${BUILD_DIR_PREFIX}/${CURRENT_ARCH}-${BUILD_TYPE}/obj/${CURRENT_V8_FOLDER}/*.o
				eval $CURRENT_BUILD_TOOL/ar r $BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE/obj/$CURRENT_V8_FOLDER/lib$CURRENT_V8_FOLDER.a "${LAST_PARAM}"
				mv $BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE/obj/$CURRENT_V8_FOLDER/lib$CURRENT_V8_FOLDER.a $DIST/$CURRENT_ARCH-$BUILD_TYPE
		done

		echo "=================================="
		echo "=================================="
		echo "Preparing libc++ and libc++abi libraries for $CURRENT_ARCH"
		echo "=================================="
		echo "=================================="
		THIRD_PARTY_OUT=$BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE/obj/buildtools/third_party
		eval $CURRENT_BUILD_TOOL/ar r $DIST/$CURRENT_ARCH-$BUILD_TYPE/libc++.a $THIRD_PARTY_OUT/libc++/libc++/*.o
		eval $CURRENT_BUILD_TOOL/ar r $DIST/$CURRENT_ARCH-$BUILD_TYPE/libc++abi.a $THIRD_PARTY_OUT/libc++abi/libc++abi/*.o

		echo "=================================="
		echo "=================================="
		echo "Copying snapshot binaries for $CURRENT_ARCH"
		echo "=================================="
		echo "=================================="
		DIST="./dist/snapshots/$CURRENT_ARCH-$BUILD_TYPE/"
		mkdir -p $DIST

		SOURCE_DIR=
		if [[ $CURRENT_ARCH == "arm64" ]] ;then
				SOURCE_DIR=$BUILD_DIR_PREFIX/$SNAPSHOT_PREFIX$CURRENT_ARCH-$BUILD_TYPE/clang_x64_v8_$CURRENT_ARCH
		elif [[ $CURRENT_ARCH == "arm" ]] ;then
				SOURCE_DIR=$BUILD_DIR_PREFIX/$SNAPSHOT_PREFIX$CURRENT_ARCH-$BUILD_TYPE/clang_x86_v8_$CURRENT_ARCH
		elif [[ $CURRENT_ARCH == "x86" ]] ;then
				SOURCE_DIR=$BUILD_DIR_PREFIX/$SNAPSHOT_PREFIX$CURRENT_ARCH-$BUILD_TYPE/clang_x86
		fi

		cp -r $SOURCE_DIR/mksnapshot $DIST

		echo "=================================="
		echo "=================================="
		echo "Preparing snapshot headers for $CURRENT_ARCH"
		echo "=================================="
		echo "=================================="

		INCLUDE="$(pwd)/dist/$CURRENT_ARCH-$BUILD_TYPE/include"
		mkdir -p $INCLUDE
		pushd $SOURCE_DIR/..
		xxd -i snapshot_blob.bin > $INCLUDE/snapshot_blob.h
		xxd -i natives_blob.bin > $INCLUDE/natives_blob.h
		popd
done

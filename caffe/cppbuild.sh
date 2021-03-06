#!/bin/bash
# This file is meant to be included by the parent cppbuild.sh script
if [[ -z "$PLATFORM" ]]; then
    pushd ..
    bash cppbuild.sh "$@" caffe
    popd
    exit
fi

case $PLATFORM in
    linux-x86)
        export CPU_ONLY=1
        export CC="$OLDCC -m32"
        export CXX="$OLDCXX -m32"
        export FC="$OLDFC -m32"
        export TOOLSET=`echo $OLDCC | sed 's/\([a-zA-Z]*\)\([0-9]\)\([0-9]\)/\1-\2.\3/'`
        export BINARY=32
        export BLAS=open
        export CUDAFLAGS=
        export USE_CUDNN=0
        ;;
    linux-x86_64)
        export CPU_ONLY=0
        export CC="$OLDCC -m64"
        export CXX="$OLDCXX -m64"
        export FC="$OLDFC -m64"
        export TOOLSET=`echo $OLDCC | sed 's/\([a-zA-Z]*\)\([0-9]\)\([0-9]\)/\1-\2.\3/'`
        export BINARY=64
        export BLAS=open
        export CUDAFLAGS="-Xcompiler -std=c++98"
        export USE_CUDNN=1
        ;;
    macosx-*)
        export CPU_ONLY=0
        export CC="clang"
        export CXX="clang++"
        export LDFLAGS="-undefined dynamic_lookup"
        export TOOLSET="clang"
        export BINARY=64
        export BLAS=atlas
        export CUDAFLAGS=
        export USE_CUDNN=1
        ;;
    *)
        echo "Error: Platform \"$PLATFORM\" is not supported"
        return 0
        ;;
esac

GLOG=0.3.5
GFLAGS=2.2.0
PROTO=3.3.0
LEVELDB=1.20
SNAPPY=1.1.4
LMDB=0.9.21
BOOST=1_63_0
CAFFE_VERSION=1.0

download https://github.com/google/glog/archive/v$GLOG.tar.gz glog-$GLOG.tar.gz
download https://github.com/gflags/gflags/archive/v$GFLAGS.tar.gz gflags-$GFLAGS.tar.gz
download https://github.com/google/protobuf/releases/download/v$PROTO/protobuf-cpp-$PROTO.tar.gz protobuf-$PROTO.tar.gz
download https://github.com/google/leveldb/archive/v$LEVELDB.tar.gz leveldb-$LEVELDB.tar.gz
download https://github.com/google/snappy/releases/download/$SNAPPY/snappy-$SNAPPY.tar.gz snappy-$SNAPPY.tar.gz
download https://github.com/LMDB/lmdb/archive/LMDB_$LMDB.tar.gz lmdb-LMDB_$LMDB.tar.gz
download http://downloads.sourceforge.net/project/boost/boost/${BOOST//_/.}/boost_$BOOST.tar.gz boost_$BOOST.tar.gz
download https://github.com/BVLC/caffe/archive/$CAFFE_VERSION.tar.gz caffe-$CAFFE_VERSION.tar.gz

mkdir -p $PLATFORM
cd $PLATFORM
INSTALL_PATH=`pwd`
mkdir -p include lib bin

OPENCV_PATH="$INSTALL_PATH/../../../opencv/cppbuild/$PLATFORM/"
HDF5_PATH="$INSTALL_PATH/../../../hdf5/cppbuild/$PLATFORM/"
OPENBLAS_PATH="$INSTALL_PATH/../../../openblas/cppbuild/$PLATFORM/"

if [[ -n "${BUILD_PATH:-}" ]]; then
    PREVIFS="$IFS"
    IFS="$BUILD_PATH_SEPARATOR"
    for P in $BUILD_PATH; do
        if [[ -d "$P/include/opencv2" ]]; then
            OPENCV_PATH="$P"
        elif [[ -f "$P/include/hdf5.h" ]]; then
            HDF5_PATH="$P"
        elif [[ -f "$P/include/openblas_config.h" ]]; then
            OPENBLAS_PATH="$P"
        fi
    done
    IFS="$PREVIFS"
fi

echo "Decompressing archives..."
tar --totals -xf ../glog-$GLOG.tar.gz || true
tar --totals -xf ../gflags-$GFLAGS.tar.gz
tar --totals -xf ../protobuf-$PROTO.tar.gz
tar --totals -xf ../leveldb-$LEVELDB.tar.gz
tar --totals -xf ../snappy-$SNAPPY.tar.gz
tar --totals -xf ../lmdb-LMDB_$LMDB.tar.gz
tar --totals -xf ../boost_$BOOST.tar.gz
tar --totals -xf ../caffe-$CAFFE_VERSION.tar.gz

export CFLAGS="-fPIC"
export CXXFLAGS="-fPIC"

cd glog-$GLOG
./configure "--prefix=$INSTALL_PATH" --disable-shared
make -j $MAKEJ
make install
cd ..

cd gflags-$GFLAGS
"$CMAKE" -DBUILD_SHARED_LIBS=OFF "-DCMAKE_INSTALL_PREFIX=$INSTALL_PATH"
make -j $MAKEJ
make install
cd ..

cd protobuf-$PROTO
./configure "--prefix=$INSTALL_PATH" --disable-shared
make -j $MAKEJ
make install
cd ..

cd leveldb-$LEVELDB
mkdir -p out-static/db out-static/helpers out-static/port out-static/table out-static/util
mkdir -p out-shared/db out-shared/helpers out-shared/port out-shared/table out-shared/util
make -j $MAKEJ
cp -a out-static/libleveldb.a "$INSTALL_PATH/lib"
cp -a include/leveldb "$INSTALL_PATH/include/"
cd ..

cd snappy-$SNAPPY
sed -i="" 's/#ifdef __SSE2__/#if 0/' snappy.cc
./configure "--prefix=$INSTALL_PATH" --disable-shared
make -j $MAKEJ
make install
cd ..

cd lmdb-LMDB_$LMDB/libraries/liblmdb
make -j $MAKEJ "CC=$CC" "XCFLAGS=$CFLAGS" "CPPFLAGS=$CXXFLAGS"
cp -a lmdb.h ../../../include/
cp -a liblmdb.a ../../../lib/
cd ../../..

cd boost_$BOOST
./bootstrap.sh --with-libraries=filesystem,system,thread
./b2 -d0 install "--prefix=$INSTALL_PATH" "address-model=$BINARY" link=static "toolset=$TOOLSET" "cxxflags=$CXXFLAGS"
cd ..
ln -sf libboost_thread.a lib/libboost_thread-mt.a

# OSX has Accelerate, but...
export C_INCLUDE_PATH="$OPENBLAS_PATH/include/"
export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"
export LIBRARY_PATH="$OPENBLAS_PATH/:$OPENBLAS_PATH/lib/"

cd caffe-$CAFFE_VERSION
patch -Np1 < ../../../caffe-nogpu.patch
cp Makefile.config.example Makefile.config
export PATH=../bin:$PATH
export CXXFLAGS="-I../include -I$OPENCV_PATH/include -I$HDF5_PATH/include"
export NVCCFLAGS="-I../include -I$OPENCV_PATH/include -I$HDF5_PATH/include $CUDAFLAGS"
export LINKFLAGS="-L../lib -L$OPENCV_PATH -L$OPENCV_PATH/lib -L$HDF5_PATH -L$HDF5_PATH/lib"
make -j $MAKEJ BLAS=$BLAS OPENCV_VERSION=3 DISTRIBUTE_DIR=.. USE_CUDNN=$USE_CUDNN lib
# Manual deploy to avoid Caffe's python build
mkdir -p ../include/caffe/proto
cp -a include/caffe/* ../include/caffe/
cp -a build/src/caffe/proto/caffe.pb.h ../include/caffe/proto
cp -a build/lib/libcaffe.so* ../lib

cd ../..

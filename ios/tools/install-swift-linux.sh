#!/bin/sh
# Swift для облачной Linux-машины (Ubuntu 24.04): пакеты swiftlang из архива Ubuntu распаковываются в /opt/swiftdeb
# (swift.org и swiftly из облака недоступны). Потом: . ios/tools/swift-env.sh && cd ios/CoreTests && swift test
set -e
V=6.0.3-2build1
D=/opt/swiftdeb
U=http://archive.ubuntu.com/ubuntu/pool
mkdir -p $D && cd $D
[ -f swiftlang_${V}_amd64.deb ] || curl -sS -O $U/universe/s/swiftlang/swiftlang_${V}_amd64.deb
[ -f libswiftlang_${V}_amd64.deb ] || curl -sS -O $U/universe/s/swiftlang/libswiftlang_${V}_amd64.deb
[ -f libxml2-16_2.14.5+dfsg-0.2_amd64.deb ] || curl -sS -O $U/main/libx/libxml2/libxml2-16_2.14.5+dfsg-0.2_amd64.deb
for f in *.deb; do dpkg-deb -x "$f" root; done
echo "swift: $D/root/usr/libexec/swift/bin"

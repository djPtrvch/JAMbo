# . ios/tools/swift-env.sh — Swift из /opt/swiftdeb в PATH (см. install-swift-linux.sh).
export LD_LIBRARY_PATH=/opt/swiftdeb/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export PATH=/opt/swiftdeb/root/usr/libexec/swift/bin:$PATH

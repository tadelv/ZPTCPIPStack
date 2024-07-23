// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZPTCPIPStack",
    targets: [
      .target(
        name: "ZPTCPIPStack",
        exclude: [
          "mbedtls/3rdparty/everest"
        ],
        cxxSettings: [
          .headerSearchPath("lwip/include"),
          .headerSearchPath("mbedtls/include"),
          .headerSearchPath("mbedtls/3rdparty/everest/include/**")
        ]
      ),
    ]
)

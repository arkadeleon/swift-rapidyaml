// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-rapidyaml",
    products: [
        .library(
            name: "RapidYAML",
            targets: ["RapidYAML"]
        ),
    ],
    targets: [
        .target(
            name: "YAMLNode",
            exclude: [
                "c4core/c4/ext",
            ],
            cxxSettings: [
                .headerSearchPath("c4core"),
                .headerSearchPath("ryml"),
            ]
        ),
        .target(
            name: "RapidYAML",
            dependencies: ["YAMLNode"]
        ),
        .testTarget(
            name: "RapidYAMLTests",
            dependencies: ["RapidYAML"]
        ),
    ]
)

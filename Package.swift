// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Furioke",
  platforms: [.macOS(.v26), .iOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0"),
  ],
  targets: [
    .target(
      name: "Furioke",
      dependencies: [
        .product(name: "Supabase", package: "supabase-swift"),
      ],
      path: "Furioke",
      resources: [
        .process("Assets.xcassets"),
      ]
    ),
  ]
)

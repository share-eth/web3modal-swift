//
//  GetWalletsV3Response.swift
//  swift-web3modal
//
//  Created by Daniel Hallman on 8/30/24.
//

import Foundation

//struct GetWalletsV3Response: Codable {
//    let count: Int
//    let listings: [String: WalletListing]
//}
//
//struct WalletListing: Codable, Identifiable {
//    let id: String
//    let app: AppLinks
//    let appType: String
//    let category: String
//    let chains: [String]
//    let description: String
//    let desktop: DesktopLinks
//    let homepage: String
//    let imageID: String
//    let imageURL: ImageURLs
//    let injected: String?
//    let metadata: Metadata
//    let mobile: MobileLinks
//    let name: String
//    let rdns: String?
//    let sdks: [String]
//    let slug: String
//    let updatedAt: String
//    let versions: [String]
//
//    enum CodingKeys: String, CodingKey {
//        case app, appType = "app_type", category, chains, description, desktop, homepage, id, imageID = "image_id", imageURL = "image_url", injected, metadata, mobile, name, rdns, sdks, slug, updatedAt, versions
//    }
//}
//
//struct AppLinks: Codable {
//    let android: String?
//    let browser: String?
//    let chrome: String?
//    let edge: String?
//    let firefox: String?
//    let ios: String?
//    let linux: String?
//    let mac: String?
//    let opera: String?
//    let safari: String?
//    let windows: String?
//}
//
//struct DesktopLinks: Codable {
//    let native: String?
//    let universal: String?
//}
//
//struct ImageURLs: Codable {
//    let lg: String
//    let md: String
//    let sm: String
//}
//
//struct Metadata: Codable {
//    let colors: Colors
//    let shortName: String
//
//    enum CodingKeys: String, CodingKey {
//        case colors
//        case shortName = "shortName"
//    }
//}
//
//struct Colors: Codable {
//    let primary: String
//    let secondary: String
//}
//
//struct MobileLinks: Codable {
//    let native: String?
//    let universal: String?
//}

// SylviaDesign: the Marginalia design language for SwiftUI, UIKit and AppKit (plan Section 4.4,
// ADR-0013). Token definitions live in SylviaDesignTokens and are re-exported here, so product
// code imports only SylviaDesign.
@_exported import SylviaDesignTokens
import Foundation

public enum SylviaDesign {
    /// The bundle holding the asset catalogs, Literata and the String Catalog.
    public static var bundle: Bundle { Bundle.module }
}

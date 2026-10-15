# UIFontMetrics against the system text style sizes

Environment: simulator: Sylvia-M0-minors-g06-design (iPhone18,3), iOS 26.5

For each mapped text style and content size: the system size (`UIFont.preferredFont`), `UIFontMetrics.scaledValue(for: default size)`, `UIFontMetrics.scaledFont(for: systemFont(ofSize: default size))`, and Sylvia's resolved role size.

| Style | Category | System | scaledValue | scaledFont | Sylvia role |
| --- | --- | --- | --- | --- | --- |
| largeTitle | XS | 31.00 | 31.67 | 32.00 | 31.00 |
| largeTitle | S | 32.00 | 32.33 | 32.00 | 32.00 |
| largeTitle | M | 33.00 | 33.33 | 33.00 | 33.00 |
| largeTitle | L | 34.00 | 34.00 | 34.00 | 34.00 |
| largeTitle | XL | 36.00 | 35.67 | 36.00 | 36.00 |
| largeTitle | XXL | 38.00 | 38.00 | 38.00 | 38.00 |
| largeTitle | XXXL | 40.00 | 39.67 | 40.00 | 40.00 |
| largeTitle | AccessibilityM | 44.00 | 43.00 | 43.00 | 44.00 |
| largeTitle | AccessibilityL | 48.00 | 47.33 | 47.00 | 48.00 |
| largeTitle | AccessibilityXL | 52.00 | 50.67 | 51.00 | 52.00 |
| largeTitle | AccessibilityXXL | 56.00 | 54.67 | 55.00 | 56.00 |
| largeTitle | AccessibilityXXXL | 60.00 | 58.00 | 58.00 | 60.00 |
| title1 | XS | 25.00 | 25.67 | 26.00 | 25.00 |
| title1 | S | 26.00 | 26.33 | 26.00 | 26.00 |
| title1 | M | 27.00 | 27.33 | 27.00 | 27.00 |
| title1 | L | 28.00 | 28.00 | 28.00 | 28.00 |
| title1 | XL | 30.00 | 29.67 | 30.00 | 30.00 |
| title1 | XXL | 32.00 | 31.33 | 31.00 | 32.00 |
| title1 | XXXL | 34.00 | 33.67 | 34.00 | 34.00 |
| title1 | AccessibilityM | 38.00 | 38.00 | 38.00 | 38.00 |
| title1 | AccessibilityL | 43.00 | 42.00 | 42.00 | 43.00 |
| title1 | AccessibilityXL | 48.00 | 47.00 | 47.00 | 48.00 |
| title1 | AccessibilityXXL | 53.00 | 50.33 | 50.00 | 53.00 |
| title1 | AccessibilityXXXL | 58.00 | 56.00 | 56.00 | 58.00 |
| title2 | XS | 19.00 | 19.00 | 19.00 | 19.00 |
| title2 | S | 20.00 | 19.67 | 20.00 | 20.00 |
| title2 | M | 21.00 | 20.33 | 20.00 | 21.00 |
| title2 | L | 22.00 | 22.00 | 22.00 | 22.00 |
| title2 | XL | 24.00 | 23.67 | 24.00 | 24.00 |
| title2 | XXL | 26.00 | 25.00 | 25.00 | 26.00 |
| title2 | XXXL | 28.00 | 26.67 | 27.00 | 28.00 |
| title2 | AccessibilityM | 34.00 | 32.33 | 32.00 | 34.00 |
| title2 | AccessibilityL | 39.00 | 37.00 | 37.00 | 39.00 |
| title2 | AccessibilityXL | 44.00 | 41.00 | 41.00 | 44.00 |
| title2 | AccessibilityXXL | 50.00 | 46.33 | 46.00 | 50.00 |
| title2 | AccessibilityXXXL | 56.00 | 52.00 | 52.00 | 56.00 |
| body | XS | 14.00 | 14.67 | 15.00 | 14.00 |
| body | S | 15.00 | 15.33 | 15.00 | 15.00 |
| body | M | 16.00 | 16.33 | 16.00 | 16.00 |
| body | L | 17.00 | 17.00 | 17.00 | 17.00 |
| body | XL | 19.00 | 18.67 | 19.00 | 19.00 |
| body | XXL | 21.00 | 20.00 | 20.00 | 21.00 |
| body | XXXL | 23.00 | 22.33 | 22.00 | 23.00 |
| body | AccessibilityM | 28.00 | 26.33 | 26.00 | 28.00 |
| body | AccessibilityL | 33.00 | 31.00 | 31.00 | 33.00 |
| body | AccessibilityXL | 40.00 | 37.00 | 37.00 | 40.00 |
| body | AccessibilityXXL | 47.00 | 43.33 | 43.00 | 47.00 |
| body | AccessibilityXXXL | 53.00 | 48.00 | 48.00 | 53.00 |
| subheadline | XS | 12.00 | 12.00 | 12.00 | 12.00 |
| subheadline | S | 13.00 | 13.67 | 14.00 | 13.00 |
| subheadline | M | 14.00 | 14.33 | 14.00 | 14.00 |
| subheadline | L | 15.00 | 15.00 | 15.00 | 15.00 |
| subheadline | XL | 17.00 | 16.67 | 17.00 | 17.00 |
| subheadline | XXL | 19.00 | 18.00 | 18.00 | 19.00 |
| subheadline | XXXL | 21.00 | 19.67 | 20.00 | 21.00 |
| subheadline | AccessibilityM | 25.00 | 23.33 | 23.00 | 25.00 |
| subheadline | AccessibilityL | 30.00 | 27.00 | 27.00 | 30.00 |
| subheadline | AccessibilityXL | 36.00 | 32.33 | 32.00 | 36.00 |
| subheadline | AccessibilityXXL | 42.00 | 37.67 | 38.00 | 42.00 |
| subheadline | AccessibilityXXXL | 49.00 | 43.67 | 44.00 | 49.00 |
| footnote | XS | 12.00 | 11.67 | 12.00 | 12.00 |
| footnote | S | 12.00 | 11.67 | 12.00 | 12.00 |
| footnote | M | 12.00 | 11.67 | 12.00 | 12.00 |
| footnote | L | 13.00 | 13.00 | 13.00 | 13.00 |
| footnote | XL | 15.00 | 14.33 | 14.00 | 15.00 |
| footnote | XXL | 17.00 | 16.00 | 16.00 | 17.00 |
| footnote | XXXL | 19.00 | 17.33 | 17.00 | 19.00 |
| footnote | AccessibilityM | 23.00 | 21.00 | 21.00 | 23.00 |
| footnote | AccessibilityL | 27.00 | 24.00 | 24.00 | 27.00 |
| footnote | AccessibilityXL | 33.00 | 29.00 | 29.00 | 33.00 |
| footnote | AccessibilityXXL | 38.00 | 33.33 | 33.00 | 38.00 |
| footnote | AccessibilityXXXL | 44.00 | 37.67 | 38.00 | 44.00 |
| caption2 | XS | 11.00 | 11.00 | 11.00 | 11.00 |
| caption2 | S | 11.00 | 11.00 | 11.00 | 11.00 |
| caption2 | M | 11.00 | 11.00 | 11.00 | 11.00 |
| caption2 | L | 11.00 | 11.00 | 11.00 | 11.00 |
| caption2 | XL | 13.00 | 15.33 | 15.00 | 13.00 |
| caption2 | XXL | 15.00 | 17.00 | 17.00 | 15.00 |
| caption2 | XXXL | 17.00 | 18.67 | 19.00 | 17.00 |
| caption2 | AccessibilityM | 20.00 | 21.00 | 21.00 | 20.00 |
| caption2 | AccessibilityL | 24.00 | 24.67 | 25.00 | 24.00 |
| caption2 | AccessibilityXL | 29.00 | 29.67 | 30.00 | 29.00 |
| caption2 | AccessibilityXXL | 34.00 | 34.67 | 35.00 | 34.00 |
| caption2 | AccessibilityXXXL | 40.00 | 40.67 | 41.00 | 40.00 |

Largest |scaledValue - system|: 6.33 pt.

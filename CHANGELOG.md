# Changelog

All notable changes to the app are documented here. When releasing, update the version in Xcode (target → General) and add an entry below.

Format: **[Version] (YYYY-MM-DD)** with sections Added / Changed / Fixed / Removed as needed.

---

## [Unreleased]

- **Added:** In-app document preview. Tapping a document (invoice, proof of purchase, etc.) in the item detail view now opens an in-app preview: PDFs and images (JPEG/PNG) are shown in a sheet with scroll/zoom. Toolbar includes **Open in Drive** to open the file in Google Drive when desired.
- **Added:** Item document attachments. You can attach documents (invoices, proof of purchase, etc.) to items. In the item detail view, a **Documents** section lists attachments; tap one to preview in the app (or open in Drive from the preview). In **Edit** mode, use **Attach document** to pick a file (PDF or image), choose a type (Invoice, Proof of purchase, Other), and optionally set a display name. Documents are stored in a dedicated **MyStuff Documents** Google Drive folder; metadata (itemId, driveFileId, kind, displayName) is stored in a new **Attachments** sheet. New spreadsheets get the Attachments sheet at creation; existing spreadsheets get it on first load. When an item is deleted, its attachment rows are removed.
- **Added:** Exports. **Settings (cog) menu** on macOS has an **Exports** section with **Export as CSV** and **Export as PDF**. CSV is a full list of all items (sorted by category then name) with headers and optional category/location names. PDF is a multi-page table of all items with thumbnails and key fields (name, category, price, date, condition, quantity, location, description). On iOS, the same options are in the **Export** toolbar menu (share icon) in the My Stuff (Gallery/List) tab. Export logic lives in `ExportService` (CSV/PDF data generation); no schema or API changes.
- **Added:** Sources section. A new **Sources** sidebar section (and tab on iOS) lists user-defined web links. Sources are stored in a **Sources** Google Sheet and managed in **Settings → Sources** (add, edit, delete). Tapping a source opens it in the same in-app browser as stores (back, forward, reload, URL bar, Open in Chrome). Last-visited URL per source is persisted in UserDefaults (`mystuff_browser_source_<id>`). New spreadsheets get an empty Sources sheet; existing spreadsheets get the sheet on first load.
- **Added:** “Search on YouTube” in the item detail dialog. A link next to “View link” opens a new **YouTube** section (tab on iOS, sidebar on macOS) with an in-app browser loading YouTube search results for the item name. Last-visited URL in the YouTube browser is persisted.
- **Added:** Quick-add to wish list in the store browser. A sparkles toolbar button adds the current page to the Wishlist category without opening the add form: the app fetches metadata from the URL (title, description, price, tags) and saves the item for later editing. A spinner is shown while the request runs.
- **Changed:** Item view and edit merged into one sheet. Tapping an item opens a single dialog; tapping Edit switches to edit mode in-place (no second sheet). Save returns to view mode with updated data; Done or Delete dismisses the sheet.
- **Changed:** Store icons now use each store’s website favicon (derived from its start URL). The SF Symbol in the Stores sheet is used as fallback when the favicon cannot be loaded. The add/edit store form no longer includes an icon picker.
- **Added:** User-controlled stores. Stores are stored in the Google Sheet (new **Stores** sheet), like Categories and Locations. In **Settings → Stores** you can add, edit, and remove stores (name, start URL, icon). The **Stores** section in the sidebar lists your stores and opens each in the in-app browser. New spreadsheets are seeded with Amazon, AliExpress, and B&H Photo; existing spreadsheets get the Stores sheet on first load. Last-visited URL per store remains in UserDefaults (`mystuff_browser_<storeId>`).
- **Added:** Thumbnail cache for Drive images. Item photos are cached in memory (NSCache) and on disk (`Caches/MyStuffThumbnails/`). Repeat views and app relaunches load from cache, reducing latency and Google Drive API usage. Disk cache is capped at 300 MB with oldest-files-first eviction.
- **Added:** AliExpress as a new store. **AliExpress** tab/sidebar entry opens aliexpress.com in the in-app browser; “Add this item” and “Extract from link” work as for other stores. Metadata extraction strips AliExpress-specific title/description boilerplate.
- **Added:** B&H Photo Video as a second store. New **B&H** tab/sidebar entry (with Amazon) opens bhphotovideo.com in the in-app browser; “Add this item” and “Extract from link” work as for Amazon. Metadata extraction strips B&H-specific title boilerplate.
- **Added:** Browse Amazon in-app. New **Amazon** tab with an embedded browser (WKWebView) and optional region picker (e.g. Amazon.com, Amazon.co.uk). Toolbar “Add this item” opens the add-item form with the current page URL prefilled and metadata extracted (title, description, price, tags) via existing “Extract from link.” Add-item form supports an optional initial URL (e.g. `ItemFormView(mode: .add(initialWebLink: url))`) for this flow.
- **Added:** Location support. Every item has an optional location. A new **Locations** tab lets you define locations and set one as the default for new items. Location is shown in the item form, detail view, list rows, and gallery popover.
- **Added:** Per-category color. Users can assign a color to each category in the Categories tab (edit → Header color). The main Items list and Gallery use that color as the category section header background.

---

## Example

## [1.0.0] (2025-01-15)

- Initial release: Google sign-in, items and categories in Sheets, photos in Drive, gallery and list views.

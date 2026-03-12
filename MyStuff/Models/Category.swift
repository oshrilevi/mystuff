import Foundation

struct Category: Identifiable, Equatable {
    let id: String
    var name: String
    var order: Int
    /// Optional parent category id. When set, this category is treated as a subcategory of the parent.
    var parentId: String?
    /// SF Symbol name for a predefined icon; used when iconFileId is nil.
    var iconSymbol: String?
    /// Drive file ID for a custom category icon image; takes precedence over iconSymbol when set.
    var iconFileId: String?

    init(id: String = UUID().uuidString, name: String, order: Int = 0, parentId: String? = nil, iconSymbol: String? = nil, iconFileId: String? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.parentId = parentId
        self.iconSymbol = iconSymbol
        self.iconFileId = iconFileId
    }

    static let columnOrder = ["id", "name", "order", "parentId", "iconSymbol", "iconFileId"]

    /// True when the category name is "Wishlist" (case-insensitive). Used to hide totals, date sort, and quantity/purchase date in UI.
    static func isWishlist(_ name: String) -> Bool {
        name.caseInsensitiveCompare("Wishlist") == .orderedSame
    }

    /// Predefined SF Symbol names for category icon picker. Search filters by substring of symbol name.
    static let predefinedIconSymbols: [String] = [
        // Folders & organization
        "folder", "folder.fill", "folder.badge.plus", "folder.badge.gearshape",
        "tag", "tag.fill", "tag.circle", "tag.circle.fill",
        "archivebox", "archivebox.fill", "tray.full", "tray.full.fill",
        "doc", "doc.fill", "doc.text", "doc.text.fill", "doc.richtext", "doc.on.doc",
        "book", "book.fill", "book.closed", "book.closed.fill", "books.vertical", "books.vertical.fill",
        // Favorites & status
        "star", "star.fill", "star.circle", "star.circle.fill", "star.square", "star.square.fill",
        "heart", "heart.fill", "heart.circle", "heart.circle.fill",
        "bookmark", "bookmark.fill", "flag", "flag.fill", "flag.circle", "flag.circle.fill",
        // Home & living
        "house", "house.fill", "house.circle", "house.circle.fill",
        "bed.double", "bed.double.fill", "sofa", "sofa.fill",
        "lamp.desk", "lamp.desk.fill", "lamp.table", "lamp.table.fill",
        "lightbulb", "lightbulb.fill", "lightbulb.slash", "lightbulb.slash.fill",
        "door.garage.closed", "door.garage.closed.fill", "key", "key.fill",
        // Tech & devices
        "laptopcomputer", "desktopcomputer", "macpro.gen1", "macpro.gen2", "macpro.gen3",
        "tv", "tv.fill", "tv.circle", "tv.circle.fill",
        "smartphone", "ipad", "ipod", "applewatch", "applewatch.watchface",
        "computer", "display", "display.trianglebadge.exclamationmark",
        "printer", "printer.fill", "scanner", "scanner.fill",
        "cable.connector", "externaldrive", "externaldrive.fill", "internaldrive", "internaldrive.fill",
        "headphones", "headphones.circle", "headphones.circle.fill",
        "speaker.wave.2", "speaker.wave.2.fill", "speaker.slash", "speaker.slash.fill",
        "gamecontroller", "gamecontroller.fill", "gamecontroller.dpad", "gamecontroller.dpad.fill",
        "camera", "camera.fill", "camera.macro", "camera.macro.fill", "video", "video.fill", "video.slash",
        "photo", "photo.fill", "photo.on.rectangle.angled", "photo.stack", "photo.stack.fill",
        // Transport & travel
        "car", "car.fill", "car.circle", "car.circle.fill",
        "airplane", "airplane.circle", "airplane.circle.fill",
        "car.side", "car.side.fill", "bus", "bus.fill", "tram.fill", "bicycle", "bicycle.circle", "bicycle.circle.fill",
        "ferry", "ferry.fill", "sailboat", "sailboat.fill", "fuelpump", "fuelpump.fill",
        "figure.walk", "figure.walk.circle", "figure.walk.diamond", "figure.walk.diamond.fill",
        "figure.run", "figure.run.circle", "figure.run.circle.fill",
        // Shopping & money
        "cart", "cart.fill", "cart.circle", "cart.circle.fill", "cart.badge.plus",
        "bag", "bag.fill", "bag.circle", "bag.circle.fill", "bag.badge.plus",
        "creditcard", "creditcard.fill", "creditcard.circle", "creditcard.circle.fill",
        "dollarsign", "dollarsign.circle", "dollarsign.circle.fill",
        "gift", "gift.fill", "gift.circle", "gift.circle.fill",
        "barcode", "barcode.viewfinder",
        // Tools & work
        "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
        "hammer", "hammer.fill", "hammer.circle", "hammer.circle.fill",
        "paintbrush", "paintbrush.fill", "paintbrush.pointed", "paintbrush.pointed.fill",
        "pencil", "pencil.circle", "pencil.circle.fill", "pencil.and.outline",
        "scissors", "scissors.badge.ellipsis", "ruler", "ruler.fill",
        "briefcase", "briefcase.fill", "briefcase.circle", "briefcase.circle.fill",
        "building.2", "building.2.fill", "building.columns", "building.columns.fill",
        // Nature & outdoors
        "leaf", "leaf.fill", "leaf.circle", "leaf.circle.fill",
        "drop", "drop.fill", "drop.circle", "drop.circle.fill", "drop.triangle", "drop.triangle.fill",
        "flame", "flame.fill", "flame.circle", "flame.circle.fill",
        "sun.max", "sun.max.fill", "sun.min", "sun.min.fill", "moon", "moon.fill", "moon.stars", "moon.stars.fill",
        "cloud", "cloud.fill", "cloud.sun", "cloud.sun.fill", "cloud.rain", "cloud.rain.fill", "cloud.snow", "cloud.snow.fill",
        "snowflake", "thermometer.sun", "thermometer.sun.fill",
        "tree", "tree.fill", "tree.circle", "tree.circle.fill",
        "bird", "bird.fill", "fish", "fish.fill", "pawprint", "pawprint.fill", "ant", "ant.fill",
        "ladybug", "ladybug.fill", "leaf.arrow.triangle.circlepath",
        // Food & drink
        "fork.knife", "fork.knife.circle", "fork.knife.circle.fill",
        "cup.and.saucer", "cup.and.saucer.fill",
        "takeoutbag.and.cup.and.straw", "takeoutbag.and.cup.and.straw.fill",
        "wineglass", "wineglass.fill", "birthday.cake", "birthday.cake.fill",
        "carrot", "carrot.fill", "apple.logo", "orange", "orange.fill",
        // Health & fitness
        "heart", "heart.fill", "heart.circle", "heart.circle.fill", "heart.text.square", "heart.text.square.fill",
        "cross.case", "cross.case.fill", "cross.vial", "cross.vial.fill",
        "pill", "pill.fill", "pill.circle", "pill.circle.fill",
        "stethoscope", "stethoscope.circle", "stethoscope.circle.fill",
        "figure.run", "figure.walk", "figure.yoga", "figure.yoga.circle", "figure.yoga.circle.fill",
        "dumbbell", "dumbbell.fill", "sportscourt", "sportscourt.fill",
        "figure.outdoor.cycle", "figure.outdoor.cycle.circle", "figure.outdoor.cycle.circle.fill",
        // Music & media
        "music.note", "music.note.list", "music.quarternote.3", "music.mic",
        "guitars", "guitars.fill", "pianokeys", "pianokeys.inverse",
        "film", "film.fill", "film.circle", "film.circle.fill",
        "play.rectangle", "play.rectangle.fill", "play.circle", "play.circle.fill",
        "photo.on.rectangle.angled", "photo.artframe", "photo.artframe.circle", "photo.artframe.circle.fill",
        "theatermasks", "theatermasks.fill", "ticket", "ticket.fill",
        // Communication & office
        "envelope", "envelope.fill", "envelope.circle", "envelope.circle.fill", "envelope.badge", "envelope.badge.fill",
        "message", "message.fill", "message.circle", "message.circle.fill",
        "phone", "phone.fill", "phone.circle", "phone.circle.fill", "phone.badge.plus", "phone.badge.plus.fill",
        "megaphone", "megaphone.fill", "bell", "bell.fill", "bell.badge", "bell.badge.fill", "bell.circle", "bell.circle.fill",
        "calendar", "calendar.circle", "calendar.circle.fill", "calendar.badge.clock", "calendar.badge.clock.rtl",
        "clock", "clock.fill", "clock.circle", "clock.circle.fill", "alarm", "alarm.fill",
        "note.text", "note.text.badge.plus", "list.bullet.clipboard", "list.bullet.clipboard.fill",
        "checklist", "checklist.rtl", "list.clipboard", "list.clipboard.fill",
        // Education & learning
        "graduationcap", "graduationcap.fill", "graduationcap.circle", "graduationcap.circle.fill",
        "book.closed", "book.closed.fill", "text.book.closed", "text.book.closed.fill",
        "pencil.and.list.clipboard", "highlighter", "highlighter.2",
        "paintpalette", "paintpalette.fill",
        // Weather & time
        "globe", "globe.americas.fill", "globe.europe.africa.fill", "globe.asia.australia.fill",
        "map", "map.fill", "map.circle", "map.circle.fill",
        "location", "location.fill", "location.circle", "location.circle.fill", "location.north", "location.north.fill",
        "mappin", "mappin.circle", "mappin.circle.fill", "mappin.and.ellipse",
        "compass.drawing", "binoculars", "binoculars.fill",
        // Misc & symbols
        "cube", "cube.fill", "cube.transparent", "cube.transparent.fill",
        "shippingbox", "shippingbox.fill", "shippingbox.circle", "shippingbox.circle.fill",
        "square.stack.3d.up", "square.stack.3d.up.fill", "square.stack.3d.down.right", "square.stack.3d.down.right.fill",
        "puzzlepiece.extension", "puzzlepiece.extension.fill",
        "safari", "safari.fill", "globe", "globe.desktop", "link", "link.circle", "link.circle.fill",
        "battery.100", "battery.100.bolt", "bolt", "bolt.fill", "bolt.circle", "bolt.circle.fill",
        "power", "power.circle", "power.circle.fill",
        "gearshape", "gearshape.fill", "gearshape.2", "gearshape.2.fill",
        "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
        "lock", "lock.fill", "lock.circle", "lock.circle.fill", "lock.open", "lock.open.fill",
        "eye", "eye.fill", "eye.slash", "eye.slash.fill", "eye.trianglebadge.exclamationmark", "eye.trianglebadge.exclamationmark.fill",
        "hand.raised", "hand.raised.fill", "hand.thumbsup", "hand.thumbsup.fill", "hand.thumbsdown", "hand.thumbsdown.fill",
        "staroflife", "staroflife.fill", "staroflife.circle", "staroflife.circle.fill",
        "figure.2.and.child.holdinghands", "person.2", "person.2.fill", "person.3", "person.3.fill",
        "teddybear", "teddybear.fill", "figure.and.child.holdinghands", "figure.2.arms.open",
    ]
}

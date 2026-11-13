import CoreGraphics
import NotchProtocol

/// Where one tile sits in Home's grid.
public struct TilePlacement: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let span: Int
    public init(row: Int, column: Int, span: Int) { self.row = row; self.column = column; self.span = span }
}

/// How Home lays out its tiles: how many columns, where each tile goes, and
/// how many didn't fit and wait behind a More tile.
public struct HomeArrangement: Equatable, Sendable {
    public let columns: Int
    /// One placement for each tile shown, in order; the tiles after them are hidden.
    public let placements: [TilePlacement]
    /// Tiles behind the More tile, which takes the last placement when this is above zero.
    public let hiddenCount: Int
    public var rows: Int { (placements.map(\.row).max() ?? -1) + 1 }
    public var width: CGFloat { HomeLayout.width(columns: columns) }
    public var height: CGFloat {
        rows > 0 ? CGFloat(rows) * HomeLayout.tileHeight + CGFloat(rows - 1) * HomeLayout.spacing : 0
    }

    /// The tile an arrow key moves to from `index`, or nil at the edge; it
    /// doesn't wrap. Left and right stay in the row. Up and down go to the
    /// next row's tile whose center is nearest, the left one on a tie, so
    /// moving from a wide tile to two small ones lands on the first.
    public func neighbor(of index: Int, _ direction: HomeDirection) -> Int? {
        guard placements.indices.contains(index) else { return placements.isEmpty ? nil : 0 }
        let current = placements[index]
        func center(_ place: TilePlacement) -> Double { Double(place.column) + Double(place.span) / 2 }
        let candidates = placements.indices.filter { other in
            let place = placements[other]
            switch direction {
            case .left: return place.row == current.row && place.column + place.span <= current.column
            case .right: return place.row == current.row && place.column >= current.column + current.span
            case .up: return place.row == current.row - 1
            case .down: return place.row == current.row + 1
            }
        }
        return candidates.min { a, b in
            let distanceA = abs(center(placements[a]) - center(current)), distanceB = abs(center(placements[b]) - center(current))
            return distanceA != distanceB ? distanceA < distanceB : placements[a].column < placements[b].column
        }
    }
}

/// An arrow key in Home.
public enum HomeDirection: Sendable { case left, right, up, down }

/// Home's grid. Like the Island, it never scrolls and never shrinks its type:
/// tiles have one size, Home grows to three rows, then widens up to six
/// columns, and only then puts the rest behind a More tile.
public enum HomeLayout {
    public static let minimumColumns = 4
    public static let maximumColumns = 6
    public static let maximumRows = 3
    public static let cellWidth: CGFloat = 100
    public static let tileHeight: CGFloat = 64
    public static let spacing: CGFloat = 8
    public static let padding: CGFloat = 16

    /// The panel width Home needs for a number of columns.
    public static func width(columns: Int) -> CGFloat {
        CGFloat(columns) * cellWidth + CGFloat(columns - 1) * spacing + 2 * padding
    }
    public static var maximumWidth: CGFloat { width(columns: maximumColumns) }

    /// Places tiles in order, each in the first free spot from the top left
    /// where it fits. A wide tile that doesn't fit the rest of a row goes
    /// down, and a later small tile fills the gap it left, so the grid has no
    /// holes while live activities stay first.
    public static func place(_ sizes: [TileSize], columns: Int) -> [TilePlacement] {
        var taken: [[Bool]] = []
        return sizes.map { size in
            let span = min(columns, size == .wide ? 2 : 1)
            var row = 0
            while true {
                while taken.count <= row { taken.append(Array(repeating: false, count: columns)) }
                if let column = (0...(columns - span)).first(where: { start in (start..<start + span).allSatisfy { !taken[row][$0] } }) {
                    for cell in column..<column + span { taken[row][cell] = true }
                    return TilePlacement(row: row, column: column, span: span)
                }
                row += 1
            }
        }
    }

    /// The fewest columns that fit every tile in three rows; at six columns,
    /// as many tiles as fit beside a small More tile.
    public static func arrange(_ sizes: [TileSize]) -> HomeArrangement {
        func rows(_ placements: [TilePlacement]) -> Int { (placements.map(\.row).max() ?? -1) + 1 }
        for columns in minimumColumns...maximumColumns {
            let placements = place(sizes, columns: columns)
            if rows(placements) <= maximumRows { return .init(columns: columns, placements: placements, hiddenCount: 0) }
        }
        var shown = sizes.count
        while shown > 0 {
            shown -= 1
            let placements = place(Array(sizes.prefix(shown)) + [.small], columns: maximumColumns)
            if rows(placements) <= maximumRows {
                return .init(columns: maximumColumns, placements: placements, hiddenCount: sizes.count - shown)
            }
        }
        return .init(columns: maximumColumns, placements: [], hiddenCount: sizes.count)
    }
}

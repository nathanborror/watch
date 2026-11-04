import Foundation

/// How far the grid is zoomed in, and on which tile position.
enum Zoom: Equatable {
    /// Every tile at its own spot.
    case grid
    /// One tile takes a 2×2 block, covering the three spots next to it.
    case expanded(Int)
    /// One tile fills the window.
    case full(Int)

    var target: Int? {
        switch self {
        case .grid: return nil
        case .expanded(let position), .full(let position): return position
        }
    }
}

/// Where each tile goes, in grid cells, for a tile count, column count, and
/// zoom. Pure, so the model (which pauses hidden tiles) and the view (which
/// places them) agree.
///
/// Positions fill the grid left to right, top to bottom.
struct GridLayout: Equatable {
    struct Cell: Equatable {
        var column: Int
        var row: Int
        var width = 1
        var height = 1

        func contains(column c: Int, row r: Int) -> Bool {
            (column..<column + width).contains(c) && (row..<row + height).contains(r)
        }
    }

    let count: Int
    let columns: Int
    let rows: Int
    let zoom: Zoom

    init(count: Int, columns: Int, zoom: Zoom) {
        self.count = count
        self.columns = max(1, min(columns, count))
        self.rows = (count + self.columns - 1) / self.columns
        // Expanding when a 2×2 block already fills the grid (four tiles) is
        // the same as full.
        if case .expanded(let position) = zoom, Self.blockFillsGrid(columns: self.columns, rows: self.rows) {
            self.zoom = .full(position)
        } else {
            self.zoom = zoom
        }
    }

    static func blockFillsGrid(columns: Int, rows: Int) -> Bool {
        columns <= 2 && rows <= 2
    }

    var blockFillsGrid: Bool { Self.blockFillsGrid(columns: columns, rows: rows) }

    /// The tile's own spot in the plain grid.
    func gridCell(_ position: Int) -> Cell {
        Cell(column: position % columns, row: position / columns)
    }

    /// The 2×2 block an expanded tile takes: its own spot plus the ones to the
    /// right and below, shifted left or up at the grid's edges.
    func block(around position: Int) -> Cell {
        let own = gridCell(position)
        let width = min(2, columns), height = min(2, rows)
        return Cell(column: min(own.column, columns - width),
                    row: min(own.row, rows - height),
                    width: width, height: height)
    }

    /// Where each visible tile goes. Positions missing from this are hidden
    /// (and paused).
    var visibleCells: [Int: Cell] {
        switch zoom {
        case .grid:
            return Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, gridCell($0)) })
        case .full(let target):
            return [target: Cell(column: 0, row: 0, width: columns, height: rows)]
        case .expanded(let target):
            let block = block(around: target)
            var cells = [target: block]
            for position in 0..<count where position != target {
                let cell = gridCell(position)
                if !block.contains(column: cell.column, row: cell.row) {
                    cells[position] = cell
                }
            }
            return cells
        }
    }

    /// Where a tile is drawn: its visible cell, or (when hidden) its own spot,
    /// so the expanded tile slides over it.
    func frameCell(_ position: Int) -> Cell {
        visibleCells[position] ?? gridCell(position)
    }
}

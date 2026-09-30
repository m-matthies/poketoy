import CoreGraphics
import Foundation
import Testing
@testable import PokeToyCore

@Suite struct ItemTests {
    @Test func gridsAreTwelveByTwelveWithKnownColors() {
        for kind in ItemKind.allCases {
            let rows = ItemArt.grids[kind]!
            #expect(rows.count == ItemArt.size, "\(kind) rows")
            for row in rows {
                #expect(row.count == ItemArt.size, "\(kind) row '\(row)'")
                for symbol in row where symbol != "." {
                    #expect(ItemArt.palette[symbol] != nil, "\(kind) uses unknown color '\(symbol)'")
                }
            }
        }
    }

    @Test func framesRenderWithOpaqueCenters() {
        for kind in ItemKind.allCases {
            let frame = ItemArt.frame(for: kind)
            #expect(frame.image.width == 12 && frame.image.height == 12)
            #expect(frame.mask.isOpaque(x: 6, y: 6), "\(kind) center")
            #expect(!frame.mask.isOpaque(x: 0, y: 0), "\(kind) corner")
        }
    }

    @Test func onlyFoodIsATreat() {
        #expect(ItemKind.apple.isTreat)
        #expect(ItemKind.oranBerry.isTreat)
        #expect(!ItemKind.pokeBall.isTreat)
    }

    @Test func itemsFallAndLandLikePets() {
        let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                visibleFrame: CGRect(x: 0, y: 50, width: 1000, height: 725))
        let world = World(screens: [screen], surfaces: [Surface(id: -1, minX: 0, maxX: 1000, y: 50, kind: .floor)])
        var item = Item(kind: .apple, body: Body(position: CGPoint(x: 500, y: 300)))
        #expect(item.state == .free)
        for _ in 0..<60 { Physics.step(&item.body, dt: 1.0 / 60, world: world) }
        #expect(item.body.surfaceID == -1)
        #expect(item.body.position.y == 50)
    }

    @Test func onlyAGroundedWobblingBallTilts() {
        var ball = Item(kind: .pokeBall, body: Body(position: .zero, surfaceID: -1), state: .flying)
        #expect(ball.wobbleAngle == 0)
        ball.state = .wobbling(petID: UUID(), wobblesLeft: 2, caught: true, timer: Item.wobbleDuration * 0.75)
        #expect(ball.wobbleAngle != 0)
        ball.body.surfaceID = nil
        #expect(ball.wobbleAngle == 0)
    }
}

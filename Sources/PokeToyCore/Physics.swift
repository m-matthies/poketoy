import CoreGraphics

public struct Body: Sendable {
    /// Bottom-center of the pet's feet, AppKit global coordinates.
    public var position: CGPoint
    public var velocity: CGVector
    /// The surface the pet stands on, or nil while airborne.
    public var surfaceID: Int?
    /// Left edge of the window being stood on when last seen, to follow sideways window moves.
    public var windowOrigin: CGFloat?

    public var isGrounded: Bool { surfaceID != nil }

    public init(position: CGPoint, velocity: CGVector = .zero, surfaceID: Int? = nil) {
        self.position = position
        self.velocity = velocity
        self.surfaceID = surfaceID
    }
}

public enum Physics {
    public static let gravity: CGFloat = 2000
    public static let terminalVelocity: CGFloat = 1600

    /// Advances the body by `dt` seconds. Returns true if it landed during this step.
    @discardableResult
    public static func step(_ body: inout Body, dt: CGFloat, world: World) -> Bool {
        if let id = body.surfaceID {
            body.velocity.dy = 0
            var x = body.position.x + body.velocity.dx * dt
            let origin = world.windowOrigins[id]
            if let origin, let previous = body.windowOrigin { x += origin - previous }
            body.windowOrigin = origin
            if let surface = world.surface(id: id, containingX: x) {
                body.position = CGPoint(x: x, y: surface.y)  // follows the surface if its window moved
            } else {
                body.position.x = x                         // walked off the edge or the window closed
                body.surfaceID = nil
            }
            return false
        }

        body.velocity.dy = max(body.velocity.dy - gravity * dt, -terminalVelocity)
        let old = body.position
        var new = CGPoint(x: old.x + body.velocity.dx * dt, y: old.y + body.velocity.dy * dt)

        if world.isWithinScreens(x: old.x), !world.isWithinScreens(x: new.x) {
            body.velocity.dx = -body.velocity.dx * 0.5
            new.x = old.x
        }

        if body.velocity.dy <= 0, let surface = world.landingSurface(x: new.x, fromY: old.y, toY: new.y) {
            body.position = CGPoint(x: new.x, y: surface.y)
            body.surfaceID = surface.id
            body.windowOrigin = world.windowOrigins[surface.id]
            body.velocity = .zero
            return true
        }
        body.position = new
        return false
    }
}

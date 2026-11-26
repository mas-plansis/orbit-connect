import Foundation

struct DiscoveryRetrySchedule {
    static let attemptsPerRound = 3
    static let delays: [TimeInterval] = [
        15 * 60,
        30 * 60,
        60 * 60,
        2 * 60 * 60,
        4 * 60 * 60,
        8 * 60 * 60,
        16 * 60 * 60,
        24 * 60 * 60,
    ]

    private(set) var attemptsInRound = 0
    private(set) var delayIndex = 0
    private(set) var retryAfter: Date?

    func canAttempt(at date: Date = Date()) -> Bool {
        guard let retryAfter else { return true }
        return date >= retryAfter
    }

    mutating func recordFailure(at date: Date = Date()) -> TimeInterval? {
        attemptsInRound += 1
        guard attemptsInRound >= Self.attemptsPerRound else { return nil }

        attemptsInRound = 0
        let delay = Self.delays[delayIndex]
        retryAfter = date.addingTimeInterval(delay)
        delayIndex = min(delayIndex + 1, Self.delays.count - 1)
        return delay
    }

    mutating func reset() {
        attemptsInRound = 0
        delayIndex = 0
        retryAfter = nil
    }
}

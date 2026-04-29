import Foundation

public struct KarmaSummary: Decodable, Hashable {
    public let total: Int
    public let level: Int
    public let breakdown: KarmaBreakdown
    public let weights: KarmaWeights

    public struct KarmaBreakdown: Decodable, Hashable {
        public let tweets: Int
        public let reactionsReceived: Int
        public let followers: Int
        public let tipsReceived: Int
        public let tasksCompleted: Int

        enum CodingKeys: String, CodingKey {
            case tweets, followers
            case reactionsReceived = "reactions_received"
            case tipsReceived = "tips_received"
            case tasksCompleted = "tasks_completed"
        }
    }

    public struct KarmaWeights: Decodable, Hashable {
        public let tweet: Int
        public let reactionReceived: Int
        public let follower: Int
        public let tipReceived: Int
        public let taskCompleted: Int

        enum CodingKeys: String, CodingKey {
            case tweet, follower
            case reactionReceived = "reactionReceived"
            case tipReceived = "tipReceived"
            case taskCompleted = "taskCompleted"
        }
    }
}

import Foundation

enum Emoji {
    // ponytail: ~140 common GitHub shortcodes; a full table (1800+) can replace this array if anyone misses one.
    static let table: [(String, String)] = [
        ("smile", "😄"), ("smiley", "😃"), ("grin", "😁"), ("grinning", "😀"), ("laughing", "😆"), ("joy", "😂"), ("rofl", "🤣"), ("sweat_smile", "😅"),
        ("wink", "😉"), ("blush", "😊"), ("innocent", "😇"), ("slightly_smiling_face", "🙂"), ("upside_down_face", "🙃"), ("relaxed", "☺️"),
        ("heart_eyes", "😍"), ("kissing_heart", "😘"), ("star_struck", "🤩"), ("yum", "😋"), ("stuck_out_tongue", "😛"), ("stuck_out_tongue_winking_eye", "😜"),
        ("zany_face", "🤪"), ("money_mouth_face", "🤑"), ("hugs", "🤗"), ("thinking", "🤔"), ("shushing_face", "🤫"), ("zipper_mouth_face", "🤐"),
        ("neutral_face", "😐"), ("expressionless", "😑"), ("no_mouth", "😶"), ("smirk", "😏"), ("unamused", "😒"), ("roll_eyes", "🙄"), ("grimacing", "😬"),
        ("relieved", "😌"), ("pensive", "😔"), ("sleepy", "😪"), ("sleeping", "😴"), ("mask", "😷"), ("face_with_thermometer", "🤒"), ("nauseated_face", "🤢"),
        ("sneezing_face", "🤧"), ("hot_face", "🥵"), ("cold_face", "🥶"), ("dizzy_face", "😵"), ("exploding_head", "🤯"), ("cowboy_hat_face", "🤠"),
        ("partying_face", "🥳"), ("sunglasses", "😎"), ("nerd_face", "🤓"), ("monocle_face", "🧐"), ("confused", "😕"), ("worried", "😟"), ("frowning", "😦"),
        ("open_mouth", "😮"), ("hushed", "😯"), ("astonished", "😲"), ("flushed", "😳"), ("pleading_face", "🥺"), ("cry", "😢"), ("sob", "😭"), ("scream", "😱"),
        ("confounded", "😖"), ("persevere", "😣"), ("disappointed", "😞"), ("sweat", "😓"), ("weary", "😩"), ("tired_face", "😫"), ("yawning_face", "🥱"),
        ("triumph", "😤"), ("rage", "😡"), ("angry", "😠"), ("cursing_face", "🤬"), ("smiling_imp", "😈"), ("skull", "💀"), ("poop", "💩"), ("clown_face", "🤡"),
        ("ghost", "👻"), ("alien", "👽"), ("robot", "🤖"), ("heart", "❤️"), ("orange_heart", "🧡"), ("yellow_heart", "💛"), ("green_heart", "💚"), ("blue_heart", "💙"),
        ("purple_heart", "💜"), ("black_heart", "🖤"), ("broken_heart", "💔"), ("sparkling_heart", "💖"), ("two_hearts", "💕"), ("100", "💯"), ("boom", "💥"),
        ("fire", "🔥"), ("sparkles", "✨"), ("star", "⭐"), ("star2", "🌟"), ("zap", "⚡"), ("sunny", "☀️"), ("cloud", "☁️"), ("rainbow", "🌈"), ("snowflake", "❄️"),
        ("wave", "👋"), ("raised_hand", "✋"), ("ok_hand", "👌"), ("v", "✌️"), ("crossed_fingers", "🤞"), ("metal", "🤘"), ("call_me_hand", "🤙"), ("point_up", "☝️"),
        ("point_down", "👇"), ("point_left", "👈"), ("point_right", "👉"), ("thumbsup", "👍"), ("+1", "👍"), ("thumbsdown", "👎"), ("-1", "👎"), ("fist", "✊"),
        ("punch", "👊"), ("clap", "👏"), ("raised_hands", "🙌"), ("open_hands", "👐"), ("pray", "🙏"), ("handshake", "🤝"), ("muscle", "💪"), ("eyes", "👀"), ("eye", "👁️"),
        ("brain", "🧠"), ("tada", "🎉"), ("confetti_ball", "🎊"), ("balloon", "🎈"), ("gift", "🎁"), ("trophy", "🏆"), ("medal", "🏅"), ("rocket", "🚀"), ("airplane", "✈️"),
        ("car", "🚗"), ("bike", "🚲"), ("house", "🏠"), ("office", "🏢"), ("coffee", "☕"), ("tea", "🍵"), ("beer", "🍺"), ("beers", "🍻"), ("wine_glass", "🍷"),
        ("pizza", "🍕"), ("hamburger", "🍔"), ("taco", "🌮"), ("sushi", "🍣"), ("cake", "🍰"), ("birthday", "🎂"), ("cookie", "🍪"), ("apple", "🍎"), ("banana", "🍌"),
        ("avocado", "🥑"), ("dog", "🐶"), ("cat", "🐱"), ("mouse", "🐭"), ("rabbit", "🐰"), ("fox_face", "🦊"), ("bear", "🐻"), ("panda_face", "🐼"), ("monkey_face", "🐵"),
        ("unicorn", "🦄"), ("bug", "🐛"), ("bee", "🐝"), ("snake", "🐍"), ("turtle", "🐢"), ("fish", "🐟"), ("whale", "🐳"), ("octopus", "🐙"), ("seedling", "🌱"),
        ("herb", "🌿"), ("four_leaf_clover", "🍀"), ("rose", "🌹"), ("sunflower", "🌻"), ("cactus", "🌵"), ("evergreen_tree", "🌲"), ("deciduous_tree", "🌳"),
        ("earth_americas", "🌎"), ("moon", "🌙"), ("white_check_mark", "✅"), ("heavy_check_mark", "✔️"), ("x", "❌"), ("warning", "⚠️"), ("question", "❓"),
        ("exclamation", "❗"), ("bulb", "💡"), ("memo", "📝"), ("pencil2", "✏️"), ("book", "📖"), ("books", "📚"), ("calendar", "📅"), ("clock", "🕐"), ("hourglass", "⏳"),
        ("alarm_clock", "⏰"), ("computer", "💻"), ("keyboard", "⌨️"), ("iphone", "📱"), ("email", "📧"), ("inbox_tray", "📥"), ("link", "🔗"), ("lock", "🔒"), ("unlock", "🔓"),
        ("key", "🔑"), ("wrench", "🔧"), ("hammer", "🔨"), ("gear", "⚙️"), ("mag", "🔍"), ("bell", "🔔"), ("mega", "📣"), ("speech_balloon", "💬"), ("thought_balloon", "💭"),
        ("zzz", "💤"), ("dollar", "💵"), ("moneybag", "💰"), ("chart_with_upwards_trend", "📈"), ("chart_with_downwards_trend", "📉"), ("package", "📦"), ("pushpin", "📌"),
        ("paperclip", "📎"), ("scissors", "✂️"), ("art", "🎨"), ("musical_note", "🎵"), ("headphones", "🎧"), ("movie_camera", "🎥"), ("camera", "📷"), ("video_game", "🎮"),
        ("soccer", "⚽"), ("basketball", "🏀"), ("tennis", "🎾"), ("running", "🏃"), ("swimmer", "🏊"), ("bicyclist", "🚴"), ("sleeping_bed", "🛏️"), ("shower", "🚿"),
        ("recycle", "♻️"), ("arrow_right", "➡️"), ("arrow_left", "⬅️"), ("arrow_up", "⬆️"), ("arrow_down", "⬇️"), ("arrows_counterclockwise", "🔄"), ("infinity", "♾️"),
        ("red_circle", "🔴"), ("green_circle", "🟢"), ("large_blue_circle", "🔵"), ("black_circle", "⚫"), ("white_circle", "⚪"),
    ]
    /// Prefix matches first, then substring matches.
    static func matches(_ q: String) -> [(String, String)] {
        let q = q.lowercased()
        guard !q.isEmpty else { return [] }
        let pre = table.filter { $0.0.hasPrefix(q) }
        let sub = table.filter { !$0.0.hasPrefix(q) && $0.0.contains(q) }
        return pre + sub
    }
}

class TeamScore {
  const TeamScore({
    required this.id,
    required this.name,
    required this.logo,
    required this.goals,
  });

  final String id;
  final String name;
  final String logo;
  final int goals;

  factory TeamScore.fromJson(Map<String, dynamic> json) => TeamScore(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Unknown team'}',
        logo: '${json['logo'] ?? ''}',
        goals: (json['goals'] as num?)?.toInt() ?? 0,
      );
}

class League {
  const League({required this.id, required this.name, required this.country});

  final String id;
  final String name;
  final String country;

  factory League.fromJson(Map<String, dynamic> json) => League(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Football'}',
        country: '${json['country'] ?? ''}',
      );
}

class LiveFixture {
  const LiveFixture({
    required this.id,
    required this.league,
    required this.status,
    required this.minute,
    required this.venue,
    required this.hasTimeline,
    required this.home,
    required this.away,
    this.isPopular = false,
    this.priority = 0,
    this.startsAt,
    this.referee,
  });

  final String id;
  final League league;
  final String status;
  final int? minute;
  final String? venue;
  final DateTime? startsAt;
  final String? referee;
  final bool hasTimeline;
  final TeamScore home;
  final TeamScore away;
  final bool isPopular;
  final int priority;

  factory LiveFixture.fromJson(Map<String, dynamic> json) => LiveFixture(
        id: '${json['id']}',
        league:
            League.fromJson(Map<String, dynamic>.from(json['league'] as Map)),
        status: '${json['status'] ?? 'live'}',
        minute: (json['minute'] as num?)?.toInt(),
        venue: json['venue'] as String?,
        startsAt: DateTime.tryParse('${json['startsAt'] ?? ''}'),
        referee: json['referee'] as String?,
        hasTimeline: json['hasTimeline'] == true,
        home:
            TeamScore.fromJson(Map<String, dynamic>.from(json['home'] as Map)),
        away:
            TeamScore.fromJson(Map<String, dynamic>.from(json['away'] as Map)),
        isPopular: json['isPopular'] == true || json['is_popular'] == true,
        priority: (json['priority'] as num?)?.toInt() ?? 0,
      );
}

class MatchEvent {
  const MatchEvent({
    required this.fingerprint,
    required this.fixtureId,
    required this.minute,
    required this.type,
    required this.detail,
    required this.teamName,
    required this.playerName,
    required this.comments,
    required this.isRedCard,
  });

  final String fingerprint;
  final String fixtureId;
  final int minute;
  final String type;
  final String detail;
  final String teamName;
  final String playerName;
  final String? comments;
  final bool isRedCard;

  bool get isCard => type.toLowerCase() == 'card';

  factory MatchEvent.fromJson(Map<String, dynamic> json) => MatchEvent(
        fingerprint: '${json['fingerprint']}',
        fixtureId: '${json['fixtureId']}',
        minute: (json['minute'] as num?)?.toInt() ?? 0,
        type: '${json['type'] ?? 'event'}',
        detail: '${json['detail'] ?? 'Match event'}',
        teamName: '${json['teamName'] ?? 'Unknown team'}',
        playerName: '${json['playerName'] ?? 'Unknown player'}',
        comments: json['comments'] as String?,
        isRedCard: json['isRedCard'] == true,
      );
}

class MatchInsights {
  const MatchInsights({
    required this.home,
    required this.away,
    this.analysis = const {},
  });

  final Map<String, dynamic> home;
  final Map<String, dynamic> away;
  final Map<String, dynamic> analysis;

  factory MatchInsights.fromJson(Map<String, dynamic> json) => MatchInsights(
        home: Map<String, dynamic>.from(json['home'] as Map? ?? const {}),
        away: Map<String, dynamic>.from(json['away'] as Map? ?? const {}),
        analysis:
            Map<String, dynamic>.from(json['analysis'] as Map? ?? const {}),
      );
}

class MkariaBetPick {
  const MkariaBetPick({
    required this.match,
    required this.market,
    required this.risk,
    this.odds,
    this.confidence,
  });

  final String match;
  final String market;
  final String risk;
  final double? odds;
  final int? confidence;

  factory MkariaBetPick.fromJson(Map<String, dynamic> json) => MkariaBetPick(
        match: json['match']?.toString() ?? 'Match',
        market: json['market']?.toString() ?? 'Market not specified',
        risk: json['risk']?.toString() ?? 'moderate',
        odds: (json['odds'] as num?)?.toDouble(),
        confidence: (json['confidence'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'match': match,
        'market': market,
        'risk': risk,
        'odds': odds,
        'confidence': confidence,
      };
}

class MkariaBetslip {
  const MkariaBetslip({
    required this.picks,
    required this.overallRisk,
    required this.note,
    this.combinedOdds,
  });

  final List<MkariaBetPick> picks;
  final String overallRisk;
  final String note;
  final double? combinedOdds;

  factory MkariaBetslip.fromJson(Map<String, dynamic> json) => MkariaBetslip(
        picks: (json['picks'] as List? ?? const [])
            .whereType<Map>()
            .map((pick) =>
                MkariaBetPick.fromJson(Map<String, dynamic>.from(pick)))
            .toList(),
        overallRisk: json['overallRisk']?.toString() ?? 'moderate',
        note: json['note']?.toString() ?? 'Verify odds before placing a bet.',
        combinedOdds: (json['combinedOdds'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'picks': picks.map((pick) => pick.toJson()).toList(),
        'overallRisk': overallRisk,
        'note': note,
        'combinedOdds': combinedOdds,
      };
}

class MkariaChatResponse {
  const MkariaChatResponse({
    required this.reply,
    this.betslip,
    this.conversationId,
  });

  final String reply;
  final MkariaBetslip? betslip;
  final String? conversationId;

  factory MkariaChatResponse.fromJson(Map<String, dynamic> json) {
    final rawSlip = json['betslip'];
    return MkariaChatResponse(
      reply: json['reply']?.toString() ?? '',
      betslip: rawSlip is Map
          ? MkariaBetslip.fromJson(Map<String, dynamic>.from(rawSlip))
          : null,
      conversationId: json['conversation_id']?.toString(),
    );
  }
}

class MkariaConversationSummary {
  const MkariaConversationSummary({
    required this.id,
    required this.title,
    this.lastMessage,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? lastMessage;
  final DateTime? updatedAt;

  factory MkariaConversationSummary.fromJson(Map<String, dynamic> json) =>
      MkariaConversationSummary(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? 'New chat',
        lastMessage: json['last_message']?.toString(),
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      );
}

class MkariaConversation {
  const MkariaConversation({
    required this.id,
    required this.title,
    required this.messages,
  });

  final String id;
  final String title;
  final List<MkariaConversationMessage> messages;

  factory MkariaConversation.fromJson(Map<String, dynamic> json) =>
      MkariaConversation(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? 'New chat',
        messages: (json['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => MkariaConversationMessage.fromJson(
                Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class MkariaConversationMessage {
  const MkariaConversationMessage({
    required this.role,
    required this.content,
    this.betslip,
  });

  final String role;
  final String content;
  final MkariaBetslip? betslip;

  factory MkariaConversationMessage.fromJson(Map<String, dynamic> json) {
    final rawSlip = json['betslip'];
    return MkariaConversationMessage(
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      betslip: rawSlip is Map
          ? MkariaBetslip.fromJson(Map<String, dynamic>.from(rawSlip))
          : null,
    );
  }
}

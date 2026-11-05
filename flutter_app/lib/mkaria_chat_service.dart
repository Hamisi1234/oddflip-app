import 'api_client.dart';
import 'models.dart';

class MkariaChatService {
  const MkariaChatService(this._apiClient);

  final ApiClient _apiClient;

  Future<MkariaChatResponse> sendMessage({
    required String message,
    List<Map<String, String>> history = const [],
    String? fixtureId,
    String? conversationId,
  }) =>
      _apiClient.sendMkariaChat(
        message: message,
        history: history,
        fixtureId: fixtureId,
        conversationId: conversationId,
      );

  Future<List<MkariaConversationSummary>> fetchConversations() =>
      _apiClient.fetchMkariaConversations();

  Future<MkariaConversation> fetchConversation(String id) =>
      _apiClient.fetchMkariaConversation(id);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';

void main() {
  group('ConversationMessage', () {
    test('copyWith returns a new instance with updated fields', () {
      final original = ConversationMessage(
        id: '1',
        role: ConversationRole.user,
        text: 'Hello',
        createdAt: DateTime(2024, 1, 1),
      );

      final updated = original.copyWith(text: 'Updated');

      expect(updated.id, '1');
      expect(updated.role, ConversationRole.user);
      expect(updated.text, 'Updated');
      expect(updated.createdAt, DateTime(2024, 1, 1));
      expect(updated.status, ConversationMessageStatus.sent);
    });

    test('copyWith preserves unchanged fields', () {
      final original = ConversationMessage(
        id: '1',
        role: ConversationRole.assistant,
        text: 'Hi',
        createdAt: DateTime(2024, 1, 1),
        status: ConversationMessageStatus.sending,
      );

      final copy = original.copyWith();

      expect(copy.id, '1');
      expect(copy.role, ConversationRole.assistant);
      expect(copy.text, 'Hi');
      expect(copy.status, ConversationMessageStatus.sending);
    });

    test('default status is sent', () {
      final message = ConversationMessage(
        id: '1',
        role: ConversationRole.user,
        text: 'Hello',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(message.status, ConversationMessageStatus.sent);
    });
  });

  group('ConversationRole', () {
    test('has user and assistant values', () {
      expect(ConversationRole.values, [
        ConversationRole.user,
        ConversationRole.assistant,
      ]);
    });
  });

  group('ConversationMessageStatus', () {
    test('has sending, sent, and error values', () {
      expect(ConversationMessageStatus.values, [
        ConversationMessageStatus.sending,
        ConversationMessageStatus.sent,
        ConversationMessageStatus.error,
      ]);
    });
  });
}

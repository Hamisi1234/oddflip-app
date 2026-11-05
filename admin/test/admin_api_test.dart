import 'package:flutter_test/flutter_test.dart';
import 'package:oddflip_admin/admin_api.dart';

void main() {
  test('parses admin dashboard stats', () {
    final stats = AdminStats.fromJson({
      'total_revenue': 10000,
      'currency': 'TZS',
      'free_trial_users': 4,
      'active_paid_users': 2,
    });

    expect(stats.totalRevenue, 10000);
    expect(stats.currency, 'TZS');
    expect(stats.freeTrialUsers, 4);
    expect(stats.activePaidUsers, 2);
  });

  test('parses paginated admin users and subscription fields', () {
    final page = AdminUserPage.fromJson({
      'current_page': 2,
      'last_page': 3,
      'total': 41,
      'data': [
        {
          'id': 42,
          'name': 'Amina',
          'email': 'amina@example.test',
          'role': 'user',
          'subscription_status': 'active_paid',
          'plan': 'monthly',
          'subscription_ends_at': '2026-11-30T12:00:00.000000Z',
        },
      ],
    });

    expect(page.currentPage, 2);
    expect(page.lastPage, 3);
    expect(page.total, 41);
    expect(page.users.single.id, 42);
    expect(page.users.single.status, 'active_paid');
    expect(page.users.single.plan, 'monthly');
  });
}

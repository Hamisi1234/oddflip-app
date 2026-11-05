<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('users')
            ->where('subscription_status', 'active')
            ->update(['subscription_status' => 'active_paid']);

        DB::table('users')
            ->where('subscription_status', 'disabled_by_admin')
            ->update(['subscription_status' => 'disabled']);
    }

    public function down(): void
    {
        DB::table('users')
            ->where('subscription_status', 'active_paid')
            ->update(['subscription_status' => 'active']);

        DB::table('users')
            ->where('subscription_status', 'disabled')
            ->update(['subscription_status' => 'disabled_by_admin']);
    }
};

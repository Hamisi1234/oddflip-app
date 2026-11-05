<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const COLUMNS = [
        'home_yellow_cards',
        'away_yellow_cards',
        'home_red_cards',
        'away_red_cards',
        'home_shots',
        'away_shots',
        'home_shots_on_target',
        'away_shots_on_target',
        'home_corners',
        'away_corners',
    ];

    public function up(): void
    {
        Schema::table('fixtures', function (Blueprint $table): void {
            foreach (self::COLUMNS as $column) {
                $table->unsignedSmallInteger($column)->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('fixtures', function (Blueprint $table): void {
            $table->dropColumn(self::COLUMNS);
        });
    }
};

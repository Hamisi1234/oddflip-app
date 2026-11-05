<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('subscriptions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('plan', 80);
            $table->unsignedInteger('amount');
            $table->char('currency', 3)->default('TZS');
            $table->string('payment_method', 30);
            $table->string('payment_reference', 100)->unique();
            $table->string('status', 30)->index();
            $table->dateTime('started_at');
            $table->dateTime('expires_at')->index();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('subscriptions');
    }
};

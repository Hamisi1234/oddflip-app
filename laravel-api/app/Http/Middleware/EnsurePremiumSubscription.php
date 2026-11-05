<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsurePremiumSubscription
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user && $user->isPremiumAccessActive()) {
            return $next($request);
        }

        if ($user && ! in_array($user->subscription_status, ['disabled', 'disabled_by_admin'], true)) {
            $user->forceFill(['subscription_status' => 'expired'])->save();
        }

        return response()->json([
            'message' => 'Your free trial or subscription has expired. Subscribe for TZS 5,000 per month to use AI match analysis.',
            'subscription_status' => $user?->subscription_status,
            'monthly_price' => 5000,
            'currency' => 'TZS',
        ], 402);
    }
}

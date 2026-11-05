<?php

namespace App\Services;

final class SportsBetMarkets
{
    private const CATEGORIES = [
        'A. Match Outcome & Results' => [
            '1', 'X', '2', '1X', 'X2', '12',
            'Draw No Bet (DNB 1)', 'Draw No Bet (DNB 2)',
            '1/1', '1/X', '1/2', 'X/1', 'X/X', 'X/2', '2/1', '2/X', '2/2',
        ],
        'B. Goals & Totals' => [
            'Over 0.5', 'Under 0.5',
            'Over 1.5', 'Under 1.5',
            'Over 2.5', 'Under 2.5',
            'Over 3.5', 'Under 3.5',
            'Home Team Over 0.5', 'Home Team Under 0.5',
            'Home Team Over 1.5', 'Home Team Under 1.5',
            'Home Team Over 2.5', 'Home Team Under 2.5',
            'Home Team Over 3.5', 'Home Team Under 3.5',
            'Away Team Over 0.5', 'Away Team Under 0.5',
            'Away Team Over 1.5', 'Away Team Under 1.5',
            'Away Team Over 2.5', 'Away Team Under 2.5',
            'Away Team Over 3.5', 'Away Team Under 3.5',
        ],
        'C. Both Teams to Score' => [
            'GG (BTTS)', 'NG', 'HT GG', '2H GG',
            'GG & Over 2.5', 'GG & Under 2.5',
        ],
        'H. Corners' => [
            'Total Corners Over 8.5', 'Under 8.5 Corners',
            'Total Corners Over 9.5', 'Under 9.5 Corners',
            'Home Team Corners Over 4.5', 'Home Team Corners Under 4.5',
            'Home Team Corners Over 5.5', 'Home Team Corners Under 5.5',
            'Away Team Corners Over 4.5', 'Away Team Corners Under 4.5',
            'Away Team Corners Over 5.5', 'Away Team Corners Under 5.5',
            'Most Corners (1)', 'Most Corners (X)', 'Most Corners (2)',
        ],
        'I. Cards & Bookings' => [
            'Total Yellow Cards Over 3.5', 'Total Yellow Cards Under 3.5',
            'Total Yellow Cards Over 4.5', 'Total Yellow Cards Under 4.5',
            'Red Card in Match (Yes)', 'Red Card in Match (No)',
        ],
        'J. Combo & Specials' => [
            '1 & Over 1.5', '2 & Over 1.5',
            'Home Win Either Half', 'Away Win Either Half',
        ],
    ];

    /**
     * @return array<int, string>
     */
    public static function options(): array
    {
        $options = [];
        foreach (self::CATEGORIES as $markets) {
            foreach ($markets as $market) {
                $options[] = $market;
            }
        }

        return array_combine(range(1, count($options)), $options) ?: [];
    }

    public static function promptList(): string
    {
        $options = [];
        $number = 1;
        foreach (self::CATEGORIES as $category => $markets) {
            $options[] = $category.':';
            foreach ($markets as $market) {
                $options[] = "#$number $market";
                $number++;
            }
        }

        $options[] = 'Player to Get a Card: unsupported by the current betslip schema and match context; do not recommend it.';

        return implode("\n", $options);
    }

    public static function optionNumber(string $market): ?int
    {
        $number = array_search($market, self::options(), true);

        return $number === false ? null : $number;
    }
}

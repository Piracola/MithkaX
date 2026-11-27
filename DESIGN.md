# Design Notes

- All reusable font sizes, text weights, spacing, insets, radii, icon sizes, row heights, and control dimensions live in `lib/theme/app_theme.dart`.
- New UI should use `AppTextSize`, `AppTextWeight`, `AppTextStyle`, `AppSpacing`, `AppInsets`, `AppRadius`, `AppIconSize`, and `AppMetric` instead of hard-coded design numbers. Add a named token first when a new reusable size is needed.
- Use `AppIcon` and `HeroAppIcons` (`lib/components/app_icons.dart`) or owned image assets. Never use built-in Material (`Icons.*`) or Cupertino (`CupertinoIcons.*`) icon sets.
- Use `SettingsCard`, `SettingsRow`, and `SettingsSwitchRow` from `lib/components/ui_components.dart` for grouped settings UI. Do not create per-screen `_settingsCard` / left-label-right-value row variants.
- Left-label/right-value rows must right-align the value text and keep the chevron at the far right.
- Use `showAppConfirmDialog`, `AppDialogSurface`, and `showAppTextEntryDialog` (`lib/components/app_confirm_dialog.dart`, `lib/components/app_dialog.dart`) for modal prompts rather than Material `AlertDialog` or `CupertinoAlertDialog`.
- Do not use Material `Switch` in app UI. Use `SettingsSwitchRow` or `CupertinoSwitch`.

## Typography

A text role is a size, a weight, and a line height together. Call sites pick a
role; they do not assemble one from a size and a height.

| role | size | weight | line height | use |
|---|---|---|---|---|
| `tiny` | 10 | 400 | 1.30 | Badges, overline labels |
| `caption` | 12 | 400 | 1.35 | Timestamps, secondary metadata |
| `footnote` | 13 | 400 | 1.38 | Dense secondary text, list subtitles |
| `callout` | 14 | 400 | 1.40 | Secondary text on desktop, compact rows |
| `body` | 15 | 400 | 1.45 | Default reading text |
| `bodyLarge` | 16 | 400 | 1.45 | Form values, composer text |
| `title` | 17 | 500 | 1.30 | Row titles, section headings, view titles |
| `display` | 22 | 600 | 1.20 | Page headings |
| `largeDisplay` | 24 | 600 | 1.20 | Hero headings, one per screen at most |

Message bodies are the exception: they use `AppTextStyle.messageBody`, which
mirrors the chat text size and its own leading, not `bodyLarge`.

- Use `AppTextStyle.<role>(color)` and `AppTextLeading.<role>`. Both carry the
  line height, so a role renders the same at every call site.
- Do not add new `height:` values in a `TextStyle`. A line height that does not
  fit any role means the role is missing, not that the call site needs an
  exception. The existing ones are counted by a budget until they migrate.
- Weight steps are `regular` 400, `medium` 500, `semibold` 600. Do not go
  heavier: at these sizes anything above 600 reads as a different typeface.
- Text below 18 must not go below 400; small type loses legibility when it is
  thinned out.
- A literal size off the ladder is a migration leftover, not a design decision.
  Fold it into the nearest step. Sizes in the tree that are deliberately not on
  the ladder:
  - Emoji and symbol glyphs are not text. Size them with `AppIconSize`, never
    with `fontSize`.
  - `lib/auth/login_view.dart` sizes a hidden one-time-code field at 1 to keep
    it out of layout. That is a layout trick, not typography.
  - A `height: 1` on a glyph box is not a line height.
- Migrating a surface means replacing its literals with roles. Changing the
  role ladder itself is a separate change, because it moves every screen at
  once.

Typography is enforced, not just documented:

- `dart run tool/typography_audit.dart` measures the tree and writes
  `build/typography/static-report.md`: off-ladder sizes, the line-height
  histogram, and the migration budget per area.
- `test/typography_budget_test.dart` holds three budgets: off-ladder sizes,
  declared line heights, and hand-picked font sizes. Each fails when it rises
  above the number in that file. Lower a budget in the PR that migrates sites;
  never raise it.
- Only the off-ladder budget is absolute, and it is at zero. The hand-picked
  and declared-height budgets are still slack: a migration lowers the tree but
  the number only moves when someone measures it again. That slack is a real
  gap — a converted area can regress back toward its old budget without the gate
  noticing — so re-measure and lower both in the same commit that migrates,
  rather than at the end.
- A size written `fontSize: AppTextSize.body` counts as a hand-picked size even
  though it names a step. It renders at that size with the theme's default
  leading, so it looks migrated while carrying the defect the ladder removes.
  Both spellings are measured; only a role states the leading too.
- The off-ladder exceptions above are not counted: they carry a
  `typography-exception` comment with the reason, and a fourth one fails a test
  until it is added to this list. The marker only excuses the one style it sits
  above.
- `test/typography_probe_test.dart` renders real screens and pins each text
  run's layout geometry in `test/typography/<scene>.json`. A batch that swaps a
  literal for a role leaves those numbers unchanged; a batch that changes the
  hierarchy moves them, and that diff is the review. Re-bless with
  `flutter test test/typography_probe_test.dart --dart-define=UPDATE_TYPOGRAPHY_BASELINE=true`
  and commit the baseline diff alongside the change.

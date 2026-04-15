# Trai Design Language

This document captures the app’s current visual language as it exists today, based on the dashboard, profile, onboarding, chat, and workouts surfaces.

Representative sources reviewed:
- [DashboardView.swift](/Users/navital/Desktop/Trai/Trai/Features/Dashboard/DashboardView.swift)
- [DashboardCards.swift](/Users/navital/Desktop/Trai/Trai/Features/Dashboard/DashboardCards.swift)
- [ProfileView.swift](/Users/navital/Desktop/Trai/Trai/Features/Profile/ProfileView.swift)
- [ProfileView+Cards.swift](/Users/navital/Desktop/Trai/Trai/Features/Profile/ProfileView+Cards.swift)
- [OnboardingView.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/OnboardingView.swift)
- [PlanReviewStepView.swift](/Users/navital/Desktop/Trai/Trai/Features/Onboarding/PlanReviewStepView.swift)
- [ChatView.swift](/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatView.swift)
- [ChatMessageViews.swift](/Users/navital/Desktop/Trai/Trai/Features/Chat/ChatMessageViews.swift)
- [WorkoutsView.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutsView.swift)
- [WorkoutsViewComponents.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutsViewComponents.swift)
- [WorkoutGoalComponents.swift](/Users/navital/Desktop/Trai/Trai/Features/Workouts/WorkoutGoalComponents.swift)
- [TraiDesignSystem.swift](/Users/navital/Desktop/Trai/Trai/Shared/DesignSystem/TraiDesignSystem.swift)

## Visual Hierarchy

Trai’s interface is built around a warm, rounded, card-first hierarchy. Most screens start with one clear focal point, then move into stacked supporting cards or compact sections. The app does not rely on sprawling dashboards or dense table layouts as the default presentation.

- Dashboard surfaces are metric-forward and modular: greeting, calories, macros, activity, weight, and workout summaries are separate cards with clear spacing.
- Profile surfaces stack large plan cards, history cards, and support cards vertically, with secondary actions pushed into buttons or links inside each card.
- Onboarding uses a more theatrical hierarchy than the rest of the app: larger headers, animated gradients, selection cards, and a strong progression rhythm.
- Chat is the most conversational surface, but it still uses structured cards for suggestions, plan updates, workouts, and reminders.
- Workouts are intentionally functional and compact: the main surface emphasizes starting a workout and viewing goals, while history, recovery, and deeper context live in sheets or toolbar actions.

## Card And Surface Treatment

The app’s dominant surface language is the Trai card: rounded rectangles with light material, subtle tint/glow, and low-contrast shadows.

- Use `traiCard(...)` as the default container for most feature cards.
- The standard card shape is a rounded rectangle, usually 16-24 points depending on the screen.
- Cards often use `.secondarySystemBackground` or `.ultraThinMaterial` as the base, then layer a light brand tint or gradient glow on top.
- Shadows are present, but they are soft and restrained. They lift the card; they do not make it feel like a floating neon panel.
- Cards often carry their own internal padding, typically 14-20 points, with section spacing sitting outside the card.
- `traiSheetBranding()` is used on presented views so sheets inherit the app accent rather than default system blue.

The app does use Liquid Glass in a few places, but it is not the default surface language for the whole UI. The card language remains material-backed and warm.

## Typography Usage

Typography is rounded, weight-forward, and intentionally legible at a glance.

- Trai has dedicated rounded font tokens: `traiHero`, `traiBold`, `traiHeadline`, and `traiLabel`.
- Large numbers and hero values are usually bold rounded text, often in the 36-48 point range.
- Section titles are typically semibold or bold, not heavy or decorative.
- Supporting text is usually `subheadline` or `caption`, with secondary foreground styling.
- Metrics and time-based values often use `monospacedDigit()` for stability.
- Copy is usually concise. Long explanatory text is reserved for onboarding, plan reviews, and deeper detail sheets.

Avoid defaulting everything to generic system body text when there is a stronger local token already in use.

## Spacing Density

The app’s density is moderate-to-compact. It feels warm and spacious, but not airy or oversized.

- The core spacing scale is the shared `TraiSpacing` token set: 4, 8, 16, 24, and 32.
- Most intra-card spacing sits in the 8-16 point range.
- Main surface sections typically use 12-24 points between major blocks.
- Onboarding can be a little looser and more expressive.
- Dashboard and workouts should stay tighter and more scan-friendly.
- Horizontal chips and compact rows are used when there are many related values; wrapping layouts are preferred over letting content overflow the screen.

The app should feel deliberate and compact, not cramped. If a screen feels too tall, the fix is usually to condense or move secondary content elsewhere, not to remove all breathing room.

## Iconography

Trai leans heavily on SF Symbols and the Trai lens identity.

- The Trai lens/hexagon icon is part of the brand and should not be replaced casually.
- Icons are usually paired with a colored chip, circle, or rounded-square background.
- Symbols are used to clarify state, category, or action, not as decorative clutter.
- The app often uses a small colored icon on the left and text on the right for scanability.
- Confirmation or success states often use green checkmarks; warnings and recovery states use orange or red; neutral navigation uses tertiary gray.

Do not introduce a new icon style family or switch the app to a more abstract or outline-heavy language.

## Color And Accent Usage

Trai uses a warm brand palette with an emphasis on orange/red energy, plus semantic colors for domain-specific data.

- `TraiColors.brandAccent` is the primary app accent and should remain the default confirmation color where possible.
- Brand gradients (`brandGradient`, `warmGradient`) are used for hero moments, onboarding headers, and some promotional surfaces.
- The warm palette is anchored by ember, flame, blaze, and coral.
- Nutrition and progress surfaces often use green, teal, orange, and blue accents depending on meaning.
- Workout recovery and readiness states use green/orange/red semantics.
- Dashboard and workout metrics often use accent plus semantic colors instead of a single monochrome accent.
- The app prefers warm system materials and subtle brand tinting over hard neon color blocks.

Avoid shifting the app into a purple-first or dark-only visual identity. The current language is warm, energetic, and approachable.

## Button Styles

Buttons follow a clear three-tier hierarchy.

- Primary actions use filled capsule buttons with white text, often with the app accent or a semantic color.
- Secondary actions use tinted capsules with colored text and softer fills.
- Tertiary actions use neutral pill-like buttons with the weakest visual weight.
- Compact and icon-only buttons are common in headers, sheets, and toolbars.
- Major confirm actions usually use `.tint(.accentColor)` and often appear as icon-only checkmarks in toolbars.
- Buttons in onboarding and plan flows are often wider and more prominent than buttons in dashboard/profile surfaces.

Do not create custom button chrome unless the local surface already uses it. Most of the app already has a strong button vocabulary.

## Sheets And Modals

Sheets are an important part of the app’s design language, and they usually feel like focused continuation surfaces rather than separate mini-apps.

- Sheets almost always use `traiSheetBranding()`.
- Presented views often keep a clear title, a short explanatory lead-in, then a stacked set of cards or sections.
- High-stakes flows such as onboarding, plan generation, and workout planning can be more expressive and animated.
- Routine detail sheets are calmer and more compact.
- Long forms are split into cards rather than presented as one huge uninterrupted form.
- Confirmation actions are usually at the top-right in a navigation bar rather than as oversized footer buttons.

Sheets should feel native to Trai, not generic system sheets.

## Toolbar Patterns

Toolbars are used for quick actions and secondary entry points.

- Toolbar items are often icon-only or very short labels.
- Common patterns include settings, done/checkmark, history, and recovery-related shortcuts.
- In workouts, toolbar actions are preferred for secondary surfaces like history and recovery rather than adding large cards to the main scroll view.
- Toolbar actions should feel light and immediately understandable.

## Scrolling Sections

The app prefers vertical scroll stacks with occasional horizontal supporting rows.

- The standard page layout is a `ScrollView` with card sections stacked vertically.
- Horizontal scroll is used for secondary content like chips, templates, or suggestion rows.
- `FlowLayout` is used when chips should wrap instead of overflowing.
- The app generally tries to keep the first screenful focused on the primary action or the primary insight.
- Secondary data should move to drill-down sheets or toolbars when it starts making the main page too tall.

This is especially true for workouts: the main tab should stay focused on starting a session and seeing core goals, not on surfacing every supporting stat at once.

## Surface-Specific Notes

### Dashboard

- Dashboard cards are modular and metric-heavy.
- Typical cards include calories, macros, today’s activity, and workout summaries.
- Values are often large, bold, and easy to scan.
- Semantic icon color and small progress bars are used to make metrics feel alive without making them busy.

### Profile

- Profile uses a stacked card layout with nutrition, workout plan, memories, chat history, exercises, and reminders.
- Plan cards are informative but still concise.
- Secondary actions like history and review sit inside cards rather than taking over the page.

### Onboarding

- Onboarding is the most expressive surface.
- It uses animated gradients, strong rounded titles, progress indicators, and selection cards.
- It can be a bit more illustrative and celebratory than the rest of the app, but it still uses the same brand colors and rounded card language.
- Prominent cards should not become visually noisy; the goal is guided progression, not spectacle.

### Chat

- Chat combines AI message bubbles with structured suggestion surfaces.
- User messages use a simple accent bubble.
- AI messages are mostly text-first, with embedded cards for meals, plans, workouts, and reminders.
- The empty state uses the Trai lens prominently and then shows suggestion cards or chip rows.
- The input bar is one of the few places where Liquid Glass is clearly appropriate because it is interactive, small, and control-like.

### Workouts

- Workouts is primarily functional and operational.
- The main surface is a compact entry point into starting a workout, viewing goals, and accessing secondary details.
- Full recovery and history are better as drill-down surfaces than as tall dashboard cards.
- Workout planning and goal setting can be more expressive, but the default workout tab should stay concise and task-oriented.

## What Not To Do

- Do not replace the Trai lens/hexagon icon with a new brand mark.
- Do not make the app purple-first, neon-heavy, or overly glossy.
- Do not use Liquid Glass as the default card language for the whole app.
- Do not turn every screen into a giant dashboard of oversized cards.
- Do not add heavy shadows, opaque borders, and glass effects all at once.
- Do not let copy get verbose when the UI can communicate the same idea with one short label.
- Do not create a brand-new one-off style for a screen unless the rest of the app is also moving that direction.
- Do not let workout, recovery, or goal surfaces crowd out the primary action on the page.

## Liquid Glass Guidance

Liquid Glass should be used selectively and with restraint.

- Good places for Liquid Glass:
  - small interactive controls
  - Trai lens or identity micro-surfaces
  - chat input controls
  - compact buttons or chips that are clearly tappable
- Good implementation pattern:
  - group related glass elements with `GlassEffectContainer`
  - apply `.glassEffect(...)` after layout and visual modifiers
  - use `.interactive()` only for elements that respond to touch
  - provide a fallback material/background for earlier iOS versions
- Not good places for Liquid Glass:
  - primary dashboard cards
  - workout summary cards
  - onboarding selection cards
  - dense data modules that already rely on the app’s material-backed card language

The existing app language is more “warm material card” than “all-glass interface.” Keep it that way unless the entire visual system is being intentionally reworked.


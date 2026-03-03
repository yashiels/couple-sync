# iOS-Native Visual Redesign

## Goal
Transform the app from a Material/vibe-coded feel to a polished iOS-native experience. Every screen should feel like it belongs on an iPhone — clean typography, Cupertino controls, translucent bars, and generous whitespace.

## Dependencies
- `google_fonts` — Inter typeface (closest open-source match to SF Pro)
- `table_calendar` — inline calendar grid for block form date picker

## Design Specification

### 1. Theme Overhaul (`app_theme.dart`)

**Colors:**
- Scaffold background: pure white `#FFFFFF` (not warm cream)
- Surface/card: `#FFFFFF` with `#F2F2F7` grouped background (iOS system gray 6)
- Primary interactive: iOS system blue `#007AFF`
- Keep rose `#E8849A` and lavender gradient only for brand moments (hero cards, overlap highlights)
- Text primary: `#000000` (not `#2D2D3A`)
- Text secondary: `#8E8E93` (iOS system gray)
- Separator: `#C6C6C8` at 0.33px or `#E5E5EA` at 1px
- Destructive: `#FF3B30` (iOS red)

**Typography (Inter):**
- Large title: 34px bold
- Title 1: 28px bold
- Title 2: 22px bold
- Title 3: 20px semibold
- Headline: 17px semibold
- Body: 17px regular
- Subhead: 15px regular
- Footnote: 13px regular
- Caption: 12px regular

**ThemeData:**
- Set `platform: TargetPlatform.iOS` to get iOS-style page transitions and back swipe
- Use `CupertinoThemeData` where appropriate
- Rounded corners: 10px for grouped cards (iOS standard)

### 2. Navigation

**AppBar → CupertinoSliverNavigationBar style:**
- Large title that collapses on scroll (use `SliverAppBar` with `expandedHeight`)
- Back button: chevron `‹` icon + previous screen title text
- Trailing actions as text buttons or icon buttons

**Bottom Tab Bar:**
- Translucent background with `BackdropFilter` blur (sigma 20)
- White at 85% opacity behind the blur
- Top border: 0.33px `#C6C6C8`
- Icons: outlined when inactive, filled when active
- Labels always visible, 10px caption text
- Active color: iOS blue `#007AFF`, inactive: `#8E8E93`

### 3. Block Form — Date/Time Picker

**Interaction:** Tap "Start" or "End" row → bottom sheet slides up

**Bottom sheet contents:**
- Drag handle: 36x5px rounded, `#C6C6C8`
- `CupertinoDatePicker` in `dateAndTime` mode
- Full-width "Confirm" button at bottom, iOS blue filled, 50px height, 10px radius

**Form layout:**
- iOS grouped list style: rounded white container on gray background
- Each field is a row with label left, value right, chevron disclosure indicator
- Category picker: horizontal scroll of pill chips
- Quick-add presets: row of rounded-rect buttons with icon + label

### 4. Screen-by-Screen Changes

**Home Screen:**
- Large title "Home" that collapses on scroll
- Hero card keeps gradient (brand moment) but with 16px corner radius
- Timezone section: clean grouped card with two rows
- Quick actions: horizontal scroll of rounded-rect buttons, not grid
- Patterns: grouped list rows with chevron

**Calendar Screen:**
- Large title "Calendar"
- Week nav header: clean with system font weight
- Legend: smaller, more subtle
- Sync button in nav bar trailing position

**Blocks Screen:**
- Large title "My Blocks"
- Grouped list cards for blocks
- Swipe-to-delete with red background (iOS style) instead of popup menu
- FAB replaced with "+" button in nav bar trailing position

**Overlap Screen:**
- Large title "Free Time"
- Filter chips: iOS-style segmented control instead of Material choice chips
- Cards: clean white with subtle separator, no elevation

**Settings Screen:**
- iOS Settings style: grouped inset lists with section headers
- Rows with leading icon, label, trailing value/chevron
- Destructive actions (sign out, unpair) in red text

**Pairing Screen:**
- Clean centered layout
- Code display: large monospace in a rounded card
- Input: iOS-style rounded text field

**Auth Screen:**
- Minimal, centered
- Sign-in buttons: full-width, 50px height, 10px radius
- Google: white background, 1px border
- Apple: black background (already correct)

### 5. Dialogs & Sheets

- Replace all `AlertDialog` with `CupertinoAlertDialog`
- Replace all `showModalBottomSheet` with iOS-style sheets (drag handle, rounded top)
- Delete confirmation: `CupertinoActionSheet` with destructive red option

### 6. Transitions

- iOS push/pop transitions (right-to-left slide) — handled by `platform: TargetPlatform.iOS`
- Back swipe gesture enabled on all pushed routes

## Implementation Order

1. Theme + typography foundation (colors, fonts, ThemeData)
2. Bottom tab bar redesign
3. AppBar / navigation pattern (large titles, back chevrons)
4. iOS grouped list widget (reusable)
5. Settings screen (showcase of grouped list pattern)
6. Block form + date/time picker
7. Home screen
8. Blocks screen (swipe-to-delete)
9. Calendar screen
10. Overlap screen
11. Auth + pairing screens
12. Dialogs and sheets migration

// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-LAYOUT-1.0 of G1-CIC-1.0: the layout mode of the home screen from the app window and the text scale (pure
// functions; the constants and the vectors of the contract are pinned by the unit tests).

export type LayoutMode = 'regular' | 'compact';

export const LAYOUT_MIN_WIDTH_DP = 360;
export const LAYOUT_MIN_HEIGHT_DP = 600;
export const COMPACT_MAP_MAX_HEIGHT_DP = 240;
export const COMPACT_MAP_MAX_WINDOW_FRACTION = 0.5;

/** width and height: the app window inside the system insets in dp; fontScale: the text scale factor. */
export function layoutMode(width: number, height: number, fontScale: number): LayoutMode {
  return width / fontScale >= LAYOUT_MIN_WIDTH_DP && height / fontScale >= LAYOUT_MIN_HEIGHT_DP ? 'regular' : 'compact';
}

/** Height of the map in the compact mode for a window of windowHeight. */
export function compactMapHeight(windowHeight: number): number {
  return Math.min(COMPACT_MAP_MAX_HEIGHT_DP, windowHeight * COMPACT_MAP_MAX_WINDOW_FRACTION);
}

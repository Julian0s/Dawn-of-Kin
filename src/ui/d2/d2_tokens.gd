class_name D2Tokens
extends RefCounted
## Semantic visual design tokens for Dawn of Kin D2.2 ("Marcos de Pedra e Eclipse").
## Values match docs/design/DAWN_OF_KIN_VISUAL_DESIGN_SYSTEM.md (UI-0 R2.3.2 homologated).

# --- Surfaces ---
const COLOR_SURFACE_BASALT_BASE: Color = Color(0.078, 0.086, 0.094, 1.0)      # #141618
const COLOR_SURFACE_BASALT_DEEP: Color = Color(0.055, 0.063, 0.075, 1.0)      # #0E1013
const COLOR_SURFACE_ALABASTER_BASE: Color = Color(0.961, 0.941, 0.902, 1.0)   # #F5F0E6
const COLOR_SURFACE_ALABASTER_EDGE: Color = Color(0.898, 0.867, 0.804, 1.0)   # #E5DDCD

# --- Gold Kintsugi Accents ---
const COLOR_ACCENT_GOLD_PRIMARY: Color = Color(0.875, 0.737, 0.447, 1.0)      # #DFBC72 (10.00:1 vs basalt)
const COLOR_ACCENT_GOLD_HIGHLIGHT: Color = Color(0.961, 0.851, 0.588, 1.0)    # #F5D996 (13.17:1 vs basalt)
const COLOR_ACCENT_GOLD_DIM: Color = Color(0.416, 0.345, 0.196, 0.65)         # #6A5832 (decorative only)

# --- Typography ---
const COLOR_TEXT_PRIMARY_IVORY: Color = Color(0.957, 0.937, 0.894, 1.0)       # #F4EFE4 (15.82:1 vs basalt)
const COLOR_TEXT_SECONDARY_MUTED: Color = Color(0.722, 0.698, 0.647, 1.0)     # #B8B2A5 (8.59:1 vs basalt)
const COLOR_TEXT_ON_ALABASTER_INK: Color = Color(0.114, 0.094, 0.075, 1.0)    # #1D1813 (15.51:1 vs alabaster)
const COLOR_TEXT_ON_ALABASTER_SUB: Color = Color(0.357, 0.294, 0.227, 1.0)    # #5B4B3A (7.36:1 vs alabaster)

# --- Semantic Feedback (WCAG 2.1 compliant pairings) ---
const COLOR_FEEDBACK_VALID_GREEN: Color = Color(0.220, 0.357, 0.165, 1.0)     # #385B2A (fill only with ivory text)
const COLOR_FEEDBACK_VALID_BRIGHT: Color = Color(0.647, 0.788, 0.545, 1.0)    # #A5C98B (9.78:1 vs basalt)
const COLOR_FEEDBACK_ERROR_ROSE: Color = Color(0.949, 0.722, 0.675, 1.0)      # #F2B8AC (10.56:1 vs basalt)
const COLOR_FEEDBACK_ERROR_DARK: Color = Color(0.776, 0.416, 0.345, 1.0)      # #C66A58 (4.84:1 vs basalt)
const COLOR_FEEDBACK_AMBER: Color = Color(0.918, 0.706, 0.392, 1.0)           # #EAB464 (9.68:1 vs basalt)

# --- Disabled / Inert Controls (Safeguard 2: clearly non-interactive) ---
const COLOR_DISABLED_FILL: Color = Color(0.0, 0.0, 0.0, 0.14)
const COLOR_DISABLED_BORDER: Color = Color(0.55, 0.51, 0.44, 0.25)
const COLOR_DISABLED_TEXT: Color = Color(0.58, 0.56, 0.50, 0.62)

# --- Interactive Plaque Time Controls (matches ui0_r2_2_d2_faithful_showcase.gd) ---
const COLOR_TIME_BTN_NORMAL_FILL: Color = Color(0.0, 0.0, 0.0, 0.18)
const COLOR_TIME_BTN_NORMAL_BORDER: Color = Color(0.875, 0.737, 0.447, 0.35)
const COLOR_TIME_BTN_HOVER_FILL: Color = Color(0.875, 0.737, 0.447, 0.16)
const COLOR_TIME_BTN_HOVER_BORDER: Color = Color(0.961, 0.851, 0.588, 0.78)
const COLOR_TIME_BTN_ACTIVE_FILL: Color = Color(0.875, 0.737, 0.447, 0.28)
const COLOR_TIME_BTN_ACTIVE_BORDER: Color = Color(0.875, 0.737, 0.447, 1.0)
const COLOR_TIME_BTN_PRESSED_FILL: Color = Color(0.875, 0.737, 0.447, 0.38)
const COLOR_TIME_BTN_EXTERNAL_PAUSE_FILL: Color = Color(0.918, 0.706, 0.392, 0.16)
const COLOR_TIME_BTN_EXTERNAL_PAUSE_BORDER: Color = Color(0.918, 0.706, 0.392, 0.55)

# --- Canonical D2.2 Shadow Pad & Polygonal Silhouettes (content-space coordinates) ---
const ATLAS_SHADOW_PAD: float = 10.0

const POLYGON_RESOURCE_ROCK: Array[Vector2] = [
	Vector2(6.0, 0.0),
	Vector2(84.0, 3.0),
	Vector2(79.0, 42.0),
	Vector2(0.0, 38.0),
]

const POLYGON_TOP_PLAQUE: Array[Vector2] = [
	Vector2(0.0, 4.0),
	Vector2(98.0, 0.0),
	Vector2(196.0, 4.0),
	Vector2(190.0, 110.0),
	Vector2(6.0, 106.0),
]

const POLYGON_FOUNDER_STELE: Array[Vector2] = [
	Vector2(6.0, 6.0),
	Vector2(108.0, 0.0),
	Vector2(104.0, 136.0),
	Vector2(0.0, 133.28),
]

const POLYGON_FOUNDER_STELE_RAISED: Array[Vector2] = [
	Vector2(6.0, 6.0),
	Vector2(108.0, 0.0),
	Vector2(104.0, 154.0),
	Vector2(0.0, 150.92),
]

const POLYGON_SLAB_MAQUETES: Array[Vector2] = [
	Vector2(8.0, 0.0),
	Vector2(176.0, 4.0),
	Vector2(170.0, 72.0),
	Vector2(0.0, 69.0),
]

const POLYGON_SLAB_CMD_BASALT: Array[Vector2] = [
	Vector2(8.0, 0.0),
	Vector2(146.0, 4.0),
	Vector2(140.0, 72.0),
	Vector2(0.0, 69.0),
]

# --- Canonical D2.2 Dimensions (1080p baseline, logical px) ---
const ROCK_CONTENT_SIZE: Vector2 = Vector2(84.0, 42.0)
const ROCK_GAP_X: float = 10.0
const ROCK_ORIGIN: Vector2 = Vector2(24.0, 20.0)
const ROCK_OFFSETS_Y: Array[float] = [0.0, 7.0, 2.0]
const ROCK_ICON_OFFSET: Vector2 = Vector2(18.0, 11.0)
const ROCK_ICON_SIZE: float = 20.0
const ROCK_LABEL_OFFSET: Vector2 = Vector2(42.0, 7.0)
const ROCK_LABEL_SIZE: Vector2 = Vector2(36.0, 26.0)
const ROCK_FONT_SIZE: float = 18.0

const PLAQUE_CONTENT_SIZE: Vector2 = Vector2(196.0, 110.0)
const PLAQUE_MARGIN_RIGHT: float = 24.0
const PLAQUE_MARGIN_TOP: float = 16.0

# --- Responsive Scale Calibration (Design System §7.1) ---
const SCALE_1080P: float = 1.0
const SCALE_720P_STRETCHED: float = 1.22
const PHYSICAL_WIDTH_720P_THRESHOLD: int = 1366
const LOGICAL_BASELINE_WIDTH: float = 1920.0
const PHYSICAL_720P_WIDTH: float = 1280.0

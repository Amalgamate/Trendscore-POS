/**
 * Single source of truth for the icon migration.
 *
 * Each entry: [semanticName, lucideCandidates, materialNames]
 *   - semanticName   : the AppIcons.<name> views use (one concept, one name)
 *   - lucideCandidates: LucideIcons.<name> options, first match wins. Several are
 *                      listed because Lucide renamed icons over time
 *                      (e.g. check-circle -> circle-check).
 *   - materialNames  : every Icons.<name> that collapses into this concept
 *                      (outlined / rounded / filled variants all become one).
 *
 * Used by scripts/gen-icons.mjs (writes lib/shared/icons.dart) and
 * scripts/migrate-icons.mjs (rewrites Icons.x -> AppIcons.y in views).
 */
export const ICON_MAP = [
  // ---- Actions
  ['add', ['plus'], ['add']],
  ['addCircle', ['circlePlus', 'plusCircle'], ['add_circle_outline']],
  ['remove', ['minus'], ['remove']],
  ['removeCircle', ['circleMinus', 'minusCircle'], ['remove_circle_outline']],
  ['close', ['x'], ['close']],
  ['check', ['check'], ['check']],
  ['checkCircle', ['circleCheck', 'checkCircle'], ['check_circle', 'check_circle_outline']],
  ['search', ['search'], ['search']],
  ['delete', ['trash2', 'trash'], ['delete_outline']],
  ['deleteForever', ['trash2', 'trash'], ['delete_forever']],
  ['deleteSweep', ['trash2', 'trash'], ['delete_sweep_outlined']],
  ['edit', ['pencil', 'squarePen', 'edit'], ['edit_outlined']],
  ['save', ['save'], ['save_outlined']],
  ['copy', ['copy'], ['copy_outlined']],
  ['share', ['share2', 'share'], ['share_outlined']],
  ['send', ['send'], ['send_outlined']],
  ['download', ['download'], ['download_outlined', 'file_download_outlined']],
  ['upload', ['upload'], ['file_upload_outlined']],
  ['print', ['printer'], ['print', 'print_outlined']],
  ['undo', ['undo2', 'undo'], ['undo']],
  ['restart', ['rotateCcw'], ['restart_alt']],
  ['sync', ['refreshCw'], ['sync']],
  ['link', ['link'], ['link']],
  ['tune', ['slidersHorizontal', 'settings2'], ['tune', 'tune_rounded']],
  ['backspace', ['delete', 'eraser'], ['backspace_outlined']],
  ['menu', ['menu'], ['menu_rounded']],
  ['playCircle', ['circlePlay', 'playCircle', 'play'], ['play_circle_outline']],

  // ---- Status & security
  ['error', ['circleAlert', 'alertCircle'], ['error_outline']],
  ['warning', ['triangleAlert', 'alertTriangle'], ['warning_amber_rounded']],
  ['info', ['info'], ['info_outline']],
  ['verified', ['badgeCheck', 'shieldCheck'], ['verified']],
  ['shield', ['shield'], ['shield_outlined']],
  ['bolt', ['zap'], ['bolt']],
  ['lock', ['lock'], ['lock_outline', 'lock_outline_rounded']],
  ['lockOpen', ['lockOpen', 'unlock'], ['lock_open_rounded']],
  ['lockClock', ['clock', 'timer'], ['lock_clock_outlined']],
  ['vpnKey', ['keyRound', 'key'], ['vpn_key_outlined']],
  ['visibility', ['eye'], ['visibility', 'visibility_outlined']],
  ['visibilityOff', ['eyeOff'], ['visibility_off', 'visibility_off_outlined']],

  // ---- Connectivity
  ['cloudSync', ['cloudSync', 'cloudUpload', 'refreshCw'], ['cloud_sync_outlined']],
  ['cloudDone', ['cloudCheck', 'cloud'], ['cloud_done_outlined']],
  ['cloudOff', ['cloudOff'], ['cloud_off_outlined']],
  ['tethering', ['radio', 'wifi'], ['wifi_tethering']],

  // ---- Direction & trend
  ['arrowForward', ['arrowRight'], ['arrow_forward']],
  ['arrowBack', ['arrowLeft'], ['arrow_back']],
  ['arrowUp', ['arrowUp'], ['arrow_upward', 'north']],
  ['arrowDown', ['arrowDown'], ['arrow_downward', 'south']],
  ['chevronRight', ['chevronRight'], ['chevron_right', 'chevron_right_rounded']],
  ['dropDown', ['chevronDown'], ['arrow_drop_down', 'expand_more']],
  ['swapHoriz', ['arrowLeftRight'], ['swap_horiz']],
  ['swapVert', ['arrowUpDown'], ['swap_vert_circle_outlined']],
  ['trendingUp', ['trendingUp'], ['trending_up']],
  ['trendingDown', ['trendingDown'], ['trending_down', 'trending_down_outlined']],

  // ---- People & business
  ['people', ['users'], ['people_outline', 'people_alt_rounded']],
  ['person', ['user'], ['person', 'person_outline']],
  ['personAdd', ['userPlus'], ['person_add_alt_1', 'person_add_outlined']],
  ['manageAccounts', ['userCog'], ['manage_accounts', 'manage_accounts_outlined']],
  ['storefront', ['store'], ['storefront', 'storefront_outlined']],
  ['business', ['building2', 'building'], ['business_outlined']],
  ['phone', ['phone'], ['phone_outlined']],
  ['phoneAndroid', ['smartphone'], ['phone_android']],
  ['pos', ['calculator'], ['point_of_sale', 'point_of_sale_rounded']],
  ['settings', ['settings'], ['settings_outlined', 'settings_rounded']],
  ['storage', ['database'], ['storage_outlined']],

  // ---- Money & reporting
  ['wallet', ['wallet'], ['account_balance_wallet_outlined', 'account_balance_wallet_rounded']],
  ['bank', ['landmark'], ['account_balance', 'account_balance_outlined']],
  ['payments', ['banknote'], ['payments_outlined']],
  ['money', ['coins', 'banknote'], ['attach_money']],
  ['creditCard', ['creditCard'], ['credit_card_outlined', 'payment']],
  ['receipt', ['receipt'], ['receipt_outlined']],
  ['receiptLong', ['receiptText', 'receipt'], ['receipt_long', 'receipt_long_outlined', 'receipt_long_rounded']],
  ['tag', ['tag'], ['tag']],
  ['barChart', ['chartColumn', 'barChart3', 'chartBar'], ['bar_chart_rounded']],
  ['analytics', ['chartLine', 'lineChart', 'chartSpline'], ['analytics_outlined']],

  // ---- Inventory & shop
  ['inventory', ['package'], ['inventory_2_outlined', 'inventory_2_rounded']],
  ['shipping', ['truck'], ['local_shipping_outlined', 'local_shipping_rounded']],
  ['cart', ['shoppingCart'], ['shopping_cart_outlined']],
  ['addToCart', ['shoppingCart'], ['add_shopping_cart']],
  ['removeFromCart', ['shoppingCart'], ['remove_shopping_cart_outlined']],
  ['bag', ['shoppingBag'], ['shopping_bag_outlined']],
  ['basket', ['shoppingBasket'], ['shopping_basket_outlined']],
  ['layers', ['layers'], ['layers_outlined']],
  ['qrCode', ['qrCode'], ['qr_code_2']],
  ['qrScanner', ['scanLine', 'scanQrCode', 'scan'], ['qr_code_scanner']],
  ['barcodeReader', ['scanBarcode', 'barcode'], ['barcode_reader']],
  ['notes', ['stickyNote', 'fileText'], ['notes']],
  ['book', ['book'], ['book_outlined']],
  ['photoAdd', ['imagePlus'], ['add_photo_alternate_outlined']],
  ['photoLibrary', ['images', 'image'], ['photo_library_outlined']],
  ['wallpaper', ['image'], ['wallpaper']],

  // ---- Category pickers (shop-defined categories)
  ['egg', ['egg'], ['egg_outlined', 'egg_alt_outlined']],
  ['bakery', ['croissant', 'cookie'], ['bakery_dining', 'bakery_dining_outlined']],
  ['drink', ['cupSoda', 'glassWater'], ['local_drink_outlined']],
  ['produce', ['leaf', 'apple'], ['eco_outlined']],
  ['snack', ['sandwich', 'popcorn'], ['fastfood_outlined']],
  ['home', ['house', 'home'], ['home_outlined']],
  ['grain', ['wheat'], ['grain', 'grass_outlined']],
  ['health', ['heartPulse', 'shieldPlus'], ['health_and_safety_outlined']],
  ['clean', ['sparkles', 'sprayCan'], ['cleaning_services_outlined']],
  ['meat', ['drumstick', 'beef'], ['set_meal_outlined']],
  ['baby', ['baby'], ['child_care_outlined']],
  ['pet', ['pawPrint', 'dog'], ['pets_outlined']],
  ['tool', ['wrench', 'hammer'], ['build_outlined']],
  ['beauty', ['flower2', 'sparkles'], ['spa_outlined']],
  ['iceCream', ['iceCreamCone', 'iceCream'], ['icecream_outlined']],
  ['oil', ['droplet', 'fuel'], ['oil_barrel_outlined']],
  ['rice', ['soup', 'wheat', 'utensils'], ['rice_bowl_outlined']],
  ['waterDrop', ['droplet', 'droplets'], ['water_drop_outlined']],
];

/** Material name -> semantic name. */
export const MATERIAL_TO_SEMANTIC = new Map(
  ICON_MAP.flatMap(([sem, , mats]) => mats.map((m) => [m, sem]))
);

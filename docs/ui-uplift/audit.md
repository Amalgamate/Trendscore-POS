# UI audit: hard-coded styling

Generated: 2026-10-07T16:47:14.572Z

Scope: `apps/shop_pos/lib/**/*.dart` excluding `theme/` and `shared/widgets/`.
Goal: **0** in every column by the end of Phase 7. Re-run with `node scripts/ui-audit.mjs`.

**Grand total: 1633**

| File | Lines | Colors.* | Color(0x…) | BorderRadius.circular | Radius.circular | fontSize: | EdgeInsets.* | Icons.* | CupertinoIcons.* | SnackBar | BoxShadow | Gradient | Total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `main.dart` | 2336 | 25 | 35 | 36 | 5 | 50 | 41 | 50 | 0 | 6 | 6 | 1 | **255** |
| `views/inventory_view.dart` | 1517 | 13 | 22 | 30 | 2 | 41 | 32 | 41 | 0 | 11 | 0 | 0 | **192** |
| `views/login_view.dart` | 1163 | 19 | 57 | 13 | 3 | 25 | 12 | 12 | 0 | 0 | 2 | 2 | **145** |
| `views/settings_view.dart` | 1224 | 7 | 8 | 26 | 0 | 34 | 25 | 33 | 0 | 12 | 0 | 0 | **145** |
| `views/reports_view.dart` | 760 | 5 | 17 | 22 | 2 | 48 | 28 | 17 | 0 | 1 | 1 | 0 | **141** |
| `views/customers_view.dart` | 1007 | 5 | 18 | 25 | 0 | 49 | 18 | 19 | 0 | 5 | 0 | 0 | **139** |
| `views/receipt_dialog.dart` | 559 | 5 | 6 | 15 | 0 | 45 | 20 | 4 | 0 | 2 | 1 | 0 | **98** |
| `views/cash_drawer_view.dart` | 431 | 7 | 4 | 22 | 0 | 24 | 16 | 16 | 0 | 3 | 1 | 0 | **93** |
| `views/purchase_orders_view.dart` | 389 | 3 | 9 | 16 | 1 | 20 | 23 | 14 | 0 | 2 | 0 | 0 | **88** |
| `views/checkout_modal.dart` | 578 | 6 | 16 | 15 | 0 | 15 | 14 | 7 | 0 | 3 | 0 | 0 | **76** |
| `views/sales_history_view.dart` | 527 | 6 | 8 | 7 | 1 | 22 | 16 | 11 | 0 | 3 | 0 | 0 | **74** |
| `pos_state.dart` | 2075 | 0 | 22 | 0 | 0 | 0 | 0 | 41 | 0 | 0 | 0 | 0 | **63** |
| `views/widgets/product_editor_dialog.dart` | 853 | 6 | 0 | 11 | 0 | 10 | 12 | 7 | 0 | 0 | 0 | 0 | **46** |
| `views/app_menu_view.dart` | 150 | 1 | 13 | 2 | 0 | 1 | 2 | 8 | 0 | 0 | 1 | 1 | **29** |
| `views/widgets/category_manager_dialog.dart` | 376 | 4 | 0 | 7 | 0 | 5 | 4 | 6 | 0 | 0 | 0 | 0 | **26** |
| `views/widgets/image_upload_widget.dart` | 280 | 7 | 1 | 4 | 0 | 2 | 2 | 2 | 0 | 2 | 2 | 0 | **22** |
| `services/image_service.dart` | 125 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **1** |
| `cart.dart` | 263 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `services/api_service.dart` | 438 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `services/favicon_service.dart` | 10 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `services/favicon_service_stub.dart` | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `services/favicon_service_web.dart` | 24 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `services/image_file_picker.dart` | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `services/image_file_picker_stub.dart` | 15 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| `services/image_file_picker_web.dart` | 66 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| **TOTAL** | | **119** | **237** | **251** | **14** | **391** | **265** | **288** | **0** | **50** | **14** | **4** | **1633** |

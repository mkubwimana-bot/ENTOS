# SME-OS FlutterFlow Screen Map

## Purpose

This document defines the first FlutterFlow screens for the SME-OS MVP.

The app will connect to Supabase as the backend. Supabase will handle:

- authentication
- tenant data
- roles and permissions
- products
- customers
- sales
- payments
- inventory
- dashboard views
- mobile/offline draft tracking

## MVP Screen Groups

### 1. Authentication

| Screen | Purpose |
|---|---|
| Login | User signs in using Supabase Auth |
| Signup / Invite Accept | User creates account or accepts company invitation |
| Forgot Password | Password reset |

### 2. Company Setup

| Screen | Purpose |
|---|---|
| Tenant Setup | Create business profile |
| Branch Setup | Confirm default branch |
| Warehouse Setup | Confirm default warehouse |
| Settings | Business preferences |

### 3. Dashboard

| Screen | Purpose |
|---|---|
| Main Dashboard | Today sales, money owed, low stock, pending mobile transactions |

Dashboard data sources:

- `vw_daily_sales`
- `vw_customer_balances`
- `vw_low_stock`
- `vw_pending_mobile_transactions`

### 4. Customers

| Screen | Purpose |
|---|---|
| Customer List | View customers |
| Customer Detail | View balance, sales, payments |
| New Customer | Create customer |
| Edit Customer | Update customer details |

Main tables:

- `parties`
- `party_type_links`
- `party_contacts`
- `party_addresses`

### 5. Products

| Screen | Purpose |
|---|---|
| Product List | View products and services |
| Product Detail | View price, stock, category |
| New Product | Create product |
| Edit Product | Update product details |

Main tables:

- `products`
- `product_types`
- `product_categories`
- `product_units`
- `product_prices`
- `product_barcodes`

### 6. Sales

| Screen | Purpose |
|---|---|
| Sales List | View invoices |
| New Sale | Create cash or credit sale |
| Sale Detail | View invoice lines and payment status |
| Void Sale | Controlled void action |

Main tables:

- `invoices`
- `invoice_lines`
- `stock_movements`

### 7. Payments

| Screen | Purpose |
|---|---|
| Payment List | View customer payments |
| Record Payment | Record payment against invoice |
| Payment Detail | View allocation |

Main tables:

- `payments`
- `payment_allocations`
- `invoices`

### 8. Inventory

| Screen | Purpose |
|---|---|
| Current Stock | View stock by product and warehouse |
| Low Stock | View items below reorder level |
| Stock Adjustment | Add or reduce stock manually |
| Stock Movement History | View movement trail |

Main tables and views:

- `stock_movements`
- `vw_current_stock`
- `vw_low_stock`

### 9. Mobile / Offline

| Screen | Purpose |
|---|---|
| Mobile Quick Sale | Fast mobile sale entry |
| Mobile Payment | Fast payment entry |
| Stock Check | Quick stock lookup |
| Sync Status | View pending or failed mobile transactions |

Main tables and views:

- `transaction_drafts`
- `sync_queue`
- `sync_logs`
- `conflict_logs`
- `vw_pending_mobile_transactions`

### 10. Reports

| Screen | Purpose |
|---|---|
| Daily Sales Report | View sales by day |
| Customer Balances | View money owed |
| Product Sales Report | View product performance |
| Gross Profit Estimate | View simple profit estimate |

Main views:

- `vw_daily_sales`
- `vw_customer_balances`
- `vw_product_sales_summary`
- `vw_gross_profit_simple`

## MVP Build Order in FlutterFlow

1. Login
2. Dashboard
3. Product List
4. New Product
5. Customer List
6. New Customer
7. New Sale
8. Record Payment
9. Current Stock
10. Reports
11. Mobile Quick Sale
12. Sync Status

## Important Design Rule

Do not build all screens at once.

Build one screen, connect it to Supabase, test it, then continue.

The first real app screen after login should be:

Dashboard
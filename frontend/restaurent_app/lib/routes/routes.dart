import 'package:Neevika/screens/Accounting/Expense/AddExpense_Screen.dart';
import 'package:Neevika/screens/Accounting/Expense/expense_Screen.dart';
import 'package:Neevika/screens/Accounting/Expense/EditExpense_Screen.dart';
import 'package:Neevika/screens/Accounting/Payroll/payroll_Screen.dart';
import 'package:Neevika/screens/Accounting/Profit_Loss/profit_loss_Screen.dart';
import 'package:Neevika/screens/Accounting/purchase_Screen.dart';
import 'package:Neevika/screens/Authentication/forgetPassword_screen.dart';
import 'package:Neevika/screens/Authentication/deleteAccount_screen.dart';
import 'package:Neevika/screens/CRM/OfferManagement_screen.dart';
import 'package:Neevika/screens/CRM/customer_details.dart';
import 'package:Neevika/screens/CRM/customer_form.dart';
import 'package:Neevika/screens/CRM/phone_input_screen.dart';
import 'package:Neevika/screens/CRM/verify_phonenumber.dart';
import 'package:Neevika/screens/ComplimentaryProfiles/ViewComplimentaryProfilesScreen.dart';
import 'package:Neevika/screens/DailyOperations/todaysSales.dart';
import 'package:Neevika/screens/DailyOperations/low_stock.dart';
import 'package:Neevika/screens/DailyOperations/running_orders.dart';
import 'package:Neevika/screens/DailyOperations/vendor_payment.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/canceledDrinksOrderScreen.dart';
import 'package:Neevika/screens/Food/menu/CanceledFoodOrderScreen.dart';
import 'package:Neevika/screens/HR/appointment_Screen.dart';
import 'package:Neevika/screens/HR/attendanceScreen.dart';
import 'package:Neevika/screens/HR/leaveApplication_Screen.dart';
import 'package:Neevika/screens/HR/staff_Screen.dart';
import 'package:Neevika/screens/HR/training_Screen.dart';
import 'package:Neevika/screens/Home/ScoreboardSceen.dart';
import 'package:Neevika/screens/IncidentReport/AddIncident_Screen.dart';
import 'package:Neevika/screens/IncidentReport/Incident_Screen.dart';
import 'package:Neevika/screens/Reports/DayEndSummary.dart';
import 'package:Neevika/screens/Reports/OtherReports/OtherReports_Screen.dart';
import 'package:Neevika/screens/Tables/BillsScreen.dart';
import 'package:Neevika/screens/Vendors/VendorAddScreen.dart';
import 'package:Neevika/screens/admin/ManageUsers.dart';
import 'package:Neevika/screens/admin/VerifyPendingUsers.dart';
import 'package:Neevika/screens/home/UnderConstruction_Screen.dart';
import 'package:flutter/material.dart';
import 'package:Neevika/screens/Admin/userRoles.dart';
import 'package:Neevika/screens/Authentication/login_screen.dart';
import 'package:Neevika/screens/Authentication/logout_screen.dart';
import 'package:Neevika/screens/Authentication/register_screen.dart';
import 'package:Neevika/screens/Admin/Dashboard/dashboard.dart';
import 'package:Neevika/screens/Drinks/drinksInventory/AddDrinksPurchaseScreen.dart';
import 'package:Neevika/screens/Drinks/drinksInventory/drinksInventoryScreen.dart';
import 'package:Neevika/screens/Drinks/drinksKitchenInventory/DrinksKitchenInventoryScreen.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksCategoriesScreen.dart';
import 'package:Neevika/screens/Drinks/drinksMenuIngredients/DrinksMenuIngredientsScreen.dart';
import 'package:Neevika/screens/Drinks/drinksOrders/drinkOrdersScreen.dart';
import 'package:Neevika/screens/Drinks/drinksMenu/DrinksMenuScreen.dart';
import 'package:Neevika/screens/Food/menu/AddMenuScreen.dart';
// import 'package:Neevika/screens/Food/menu/CategoriesScreen.dart';

import 'package:Neevika/screens/Home/home_screen.dart';
import 'package:Neevika/screens/Food/Inventory/InventoryScreen.dart';
import 'package:Neevika/screens/Food/menu/MenuScreen.dart';
import 'package:Neevika/screens/Tables/TablesScreen.dart';
import 'package:Neevika/screens/Food/orders/OrdersScreen.dart';
import 'package:Neevika/screens/Food/Inventory/AddPurchaseScreen.dart';
import 'package:Neevika/screens/Food/kitchenInventory/KitchenInventoryScreen.dart';
import 'package:Neevika/screens/Food/ingredients/IngredientsScreen.dart';
import 'package:Neevika/screens/Food/menuIngredients/MenuIngredientsScreen.dart';
import 'package:Neevika/screens/Vendors/VendorScreen.dart';

class AppRoutes {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    print('Navigating to route: ${settings.name}');
    final uri = Uri.parse(settings.name ?? '');

    switch (uri.path) {
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case '/register':
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      // case '/change-password':
      //   return MaterialPageRoute(builder: (_) => const ChangePasswordScreen());
      case '/logout':
        return MaterialPageRoute(builder: (_) => const LogoutScreen());
      case '/':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/home':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/menu':
        return MaterialPageRoute(builder: (_) => const MenuScreen());
      // case '/view-categories':
      //   return MaterialPageRoute(builder: (_) => const CategoryTileScreen());
      case '/view-drinks-categories':
        return MaterialPageRoute(
          builder: (_) => const DrinksCategoryTileScreen(),
        );
      case '/drinks':
        return MaterialPageRoute(builder: (_) => const DrinksMenuScreen());
      case '/tables':
        return MaterialPageRoute(builder: (_) => const ViewTableScreen());
      case '/orders':
        return MaterialPageRoute(builder: (_) => ViewOrdersScreen());
      case '/food-canceled-orders':
        return MaterialPageRoute(builder: (_) => CanceledFoodsOrderScreen());
      case '/drink-orders':
        return MaterialPageRoute(builder: (_) => ViewDrinkOrdersScreen());
      case '/drink-canceled-orders':
        return MaterialPageRoute(builder: (_) => CanceledDrinksOrdersScreen());
      case '/under_construction':
        return MaterialPageRoute(builder: (_) => UnderConstructionScreen());
      case '/inventory':
        return MaterialPageRoute(builder: (_) => const ViewInventoryScreen());
      case '/drinks-inventory':
        return MaterialPageRoute(
          builder: (_) => const ViewDrinksInventoryScreen(),
        );
      case '/add_purchase':
        return MaterialPageRoute(builder: (_) => AddPurchasePage());
      case '/add_drinks_purchase':
        return MaterialPageRoute(builder: (_) => AddDrinksPurchasePage());
      case '/kitchen_inventory':
        return MaterialPageRoute(builder: (_) => KitchenInventoryPage());
      case '/drinks-kitchen_inventory':
        return MaterialPageRoute(builder: (_) => DrinksKitchenInventoryPage());
      case '/drinks-menu-ingredients':
        return MaterialPageRoute(builder: (_) => DrinksMenuIngredientsScreen());
      case '/add_menu':
        return MaterialPageRoute(builder: (_) => AddMenuPage());
      case '/ingredients':
        return MaterialPageRoute(builder: (_) => IngredientScreen());
      case '/menu-ingredients':
        return MaterialPageRoute(builder: (_) => MenuIngredientsScreen());
      case '/Dashboard':
        return MaterialPageRoute(builder: (_) => DashboardScreen());
      case '/vendor':
        return MaterialPageRoute(builder: (_) => ViewVendorScreen());
      case '/user-roles':
        return MaterialPageRoute(builder: (_) => ViewUserRoleScreen());
      case '/running-orders':
        return MaterialPageRoute(builder: (_) => RunningOrdersPage());
      case '/todays-sales':
        return MaterialPageRoute(builder: (_) => TodaysSalesDashboard());
      case '/low-stock':
        return MaterialPageRoute(builder: (_) => LowStockPage());
      case '/day-end-summary':
        return MaterialPageRoute(builder: (_) => DayEndSummaryScreen());
      case '/vendor-payment':
        return MaterialPageRoute(builder: (_) => VendorPayment());
      case '/scoreboard':
        return MaterialPageRoute(builder: (_) => ScoreboardScreen());
      case '/customer-details':
        return MaterialPageRoute(builder: (_) => CustomerDetailsPage());
      case '/add-vendor':
        return MaterialPageRoute(builder: (_) => AddVendorScreen());
      case '/attendance':
        return MaterialPageRoute(builder: (_) => AttendanceScreen());
      case '/staff':
        return MaterialPageRoute(builder: (_) => AttendanceTableScreen());
      case '/appointment-letter':
        return MaterialPageRoute(builder: (_) => AppointmentLetterScreen());
      case '/leave-letter':
        return MaterialPageRoute(builder: (_) => LeaveLetterScreen());
      case '/training':
        return MaterialPageRoute(builder: (_) => TrainingVideoScreen());
      case '/expense':
        return MaterialPageRoute(builder: (_) => ExpenseScreen());
      case '/add-expense':
        return MaterialPageRoute(builder: (_) => AddExpensePage());
      case '/purchase':
        return MaterialPageRoute(builder: (_) => PurchaseScreen());
      case '/payroll':
        return MaterialPageRoute(builder: (_) => PayrollListScreen());
      case '/profit-loss':
        return MaterialPageRoute(builder: (_) => ProfitLossScreen());
      case '/other-reports':
        return MaterialPageRoute(builder: (_) => AllReportsScreen());
      case '/delete-account':
        return MaterialPageRoute(builder: (_) => DeleteAccountScreen());
      case '/compliemnetary-profiles':
        return MaterialPageRoute(builder: (_) => ViewComplimentaryProfilesScreen());
      case '/verify-phone-number':
        return MaterialPageRoute(builder: (_) => VerifyPhoneNumberScreen());

      case '/customer-form':
        {
          // Extract query param from URL: /customer-form?tableCode=1
          final tableCode = uri.queryParameters['tableCode'];
          return MaterialPageRoute(
            builder: (_) => PhoneInputScreen(tableCode: tableCode),
          );
        }

      case '/offer-management':
        return MaterialPageRoute(builder: (_) => OfferManagementPage());

      case '/incident-report':
        return MaterialPageRoute(builder: (_) => IncidentScreen());

      case '/add-incident-report':
        return MaterialPageRoute(builder: (_) => AddIncidentPage());
      case '/bills':
        return MaterialPageRoute(builder: (_) => BillsPage());
      case '/unverified-users':
        return MaterialPageRoute(builder: (_) => ViewUsersScreen());
      case '/manage-users':
        return MaterialPageRoute(builder: (_) => AdminUsersScreen());

      default:
        print('Route not found: ${settings.name}');
        debugPrintStack(label: 'Route not found stack trace:');
        return _errorRoute(settings.name);
    }
  }

  static Route<dynamic> _errorRoute(String? routeName) {
    return MaterialPageRoute(
      builder:
          (_) => Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Text(
                'Route not found: $routeName',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
    );
  }
}

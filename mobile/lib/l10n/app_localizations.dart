import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('vi')];

  /// Application title displayed in app bar and task switcher
  ///
  /// In vi, this message translates to:
  /// **'Uống thuốc'**
  String get appTitle;

  /// Bottom navigation label for Home tab
  ///
  /// In vi, this message translates to:
  /// **'Trang chủ'**
  String get navHome;

  /// Bottom navigation label for Create Plan tab
  ///
  /// In vi, this message translates to:
  /// **'Tạo kế hoạch'**
  String get navCreatePlan;

  /// Bottom navigation label for Drug tab
  ///
  /// In vi, this message translates to:
  /// **'Thuốc'**
  String get navDrug;

  /// Bottom navigation label for Lookup tab
  ///
  /// In vi, this message translates to:
  /// **'Tra cứu'**
  String get navLookup;

  /// AppBar title for lookup screen
  ///
  /// In vi, this message translates to:
  /// **'Tra cứu'**
  String get lookupTitle;

  /// Segment label for drug lookup section
  ///
  /// In vi, this message translates to:
  /// **'Thuốc'**
  String get lookupSectionDrugs;

  /// Segment label for interactions section
  ///
  /// In vi, this message translates to:
  /// **'Tương tác'**
  String get lookupSectionInteractions;

  /// Segment label for active ingredients section
  ///
  /// In vi, this message translates to:
  /// **'Hoạt chất'**
  String get lookupSectionIngredients;

  /// Title of drug lookup section
  ///
  /// In vi, this message translates to:
  /// **'Tra cứu thuốc'**
  String get lookupDrugSectionTitle;

  /// Subtitle of drug lookup section
  ///
  /// In vi, this message translates to:
  /// **'Tìm theo tên thương mại hoặc hoạt chất để xem thông tin chi tiết.'**
  String get lookupDrugSectionSubtitle;

  /// Input hint for drug search
  ///
  /// In vi, this message translates to:
  /// **'Ví dụ: Paracetamol, Hapacol...'**
  String get lookupDrugSearchHint;

  /// Title of interaction-by-drug section
  ///
  /// In vi, this message translates to:
  /// **'Kiểm tra tương tác theo thuốc'**
  String get lookupInteractionSectionTitle;

  /// Subtitle of interaction-by-drug section
  ///
  /// In vi, this message translates to:
  /// **'Chọn từ 2 thuốc trở lên để kiểm tra các cặp có nguy cơ tương tác.'**
  String get lookupInteractionSectionSubtitle;

  /// Input hint for adding drugs to interaction check
  ///
  /// In vi, this message translates to:
  /// **'Nhập tên thuốc để thêm...'**
  String get lookupInteractionDrugSearchHint;

  /// Title of interaction-by-ingredients section
  ///
  /// In vi, this message translates to:
  /// **'Kiểm tra theo danh sách hoạt chất'**
  String get lookupIngredientsSectionTitle;

  /// Subtitle of interaction-by-ingredients section
  ///
  /// In vi, this message translates to:
  /// **'Thêm hoạt chất trực tiếp để kiểm tra tương tác dược lý.'**
  String get lookupIngredientsSectionSubtitle;

  /// Input hint for active ingredient search
  ///
  /// In vi, this message translates to:
  /// **'Nhập hoạt chất (ví dụ: Paracetamol)'**
  String get lookupIngredientSearchHint;

  /// Title for single ingredient lookup
  ///
  /// In vi, this message translates to:
  /// **'Tra cứu 1 hoạt chất'**
  String get lookupSingleIngredientTitle;

  /// Subtitle for single ingredient lookup
  ///
  /// In vi, this message translates to:
  /// **'Xem toàn bộ tương tác liên quan tới một hoạt chất cụ thể.'**
  String get lookupSingleIngredientSubtitle;

  /// Input hint for one ingredient lookup
  ///
  /// In vi, this message translates to:
  /// **'Ví dụ: Levocetirizine'**
  String get lookupSingleIngredientHint;

  /// Primary action for drug interaction checking
  ///
  /// In vi, this message translates to:
  /// **'Kiểm tra tương tác'**
  String get lookupActionCheckInteractions;

  /// Primary action for active ingredient interaction checking
  ///
  /// In vi, this message translates to:
  /// **'Kiểm tra theo hoạt chất'**
  String get lookupActionCheckByIngredients;

  /// Primary action for single ingredient lookup
  ///
  /// In vi, this message translates to:
  /// **'Tra cứu hoạt chất'**
  String get lookupActionLookupIngredient;

  /// Secondary action to clear selected chips
  ///
  /// In vi, this message translates to:
  /// **'Xóa chọn'**
  String get lookupActionClearSelection;

  /// Hint shown when keyword length is below minimum
  ///
  /// In vi, this message translates to:
  /// **'Nhập ít nhất 2 ký tự để bắt đầu tra cứu thuốc.'**
  String get lookupHintEnterAtLeast2Chars;

  /// Hint shown when no drugs found
  ///
  /// In vi, this message translates to:
  /// **'Không tìm thấy thuốc phù hợp với từ khóa hiện tại.'**
  String get lookupHintNoDrugResult;

  /// Hint shown when no selected drugs
  ///
  /// In vi, this message translates to:
  /// **'Chưa chọn thuốc nào.'**
  String get lookupHintNoSelectedDrugs;

  /// Hint shown when no selected active ingredients
  ///
  /// In vi, this message translates to:
  /// **'Chưa chọn hoạt chất nào.'**
  String get lookupHintNoSelectedIngredients;

  /// Fallback label for unknown active ingredient
  ///
  /// In vi, this message translates to:
  /// **'Không rõ hoạt chất'**
  String get lookupUnknownIngredient;

  /// Subtitle label for active ingredient suggestion items
  ///
  /// In vi, this message translates to:
  /// **'Hoạt chất gợi ý'**
  String get lookupIngredientSuggestionLabel;

  /// Title for interaction results by selected drugs
  ///
  /// In vi, this message translates to:
  /// **'Kết quả tương tác theo thuốc'**
  String get lookupResultByDrugsTitle;

  /// Title for interaction results by selected active ingredients
  ///
  /// In vi, this message translates to:
  /// **'Kết quả theo danh sách hoạt chất'**
  String get lookupResultByIngredientsTitle;

  /// Title for interaction results by single active ingredient
  ///
  /// In vi, this message translates to:
  /// **'Kết quả theo một hoạt chất'**
  String get lookupResultBySingleIngredientTitle;

  /// Message when no interactions are found
  ///
  /// In vi, this message translates to:
  /// **'Chưa ghi nhận tương tác trong dữ liệu hiện tại.'**
  String get lookupNoInteractions;

  /// Total interactions chip label
  ///
  /// In vi, this message translates to:
  /// **'Tổng: {count}'**
  String lookupSummaryTotal(int count);

  /// Pair count label in grouped interaction cards
  ///
  /// In vi, this message translates to:
  /// **'{count} cặp'**
  String lookupGroupPairCount(int count);

  /// Fallback label when interaction pair text is missing
  ///
  /// In vi, this message translates to:
  /// **'Cặp tương tác chưa xác định'**
  String get lookupUnknownInteractionPair;

  /// Normalized severity label: contraindicated
  ///
  /// In vi, this message translates to:
  /// **'Chống chỉ định'**
  String get lookupSeverityContraindicated;

  /// Normalized severity label: major
  ///
  /// In vi, this message translates to:
  /// **'Nghiêm trọng'**
  String get lookupSeverityMajor;

  /// Normalized severity label: moderate
  ///
  /// In vi, this message translates to:
  /// **'Trung bình'**
  String get lookupSeverityModerate;

  /// Normalized severity label: minor
  ///
  /// In vi, this message translates to:
  /// **'Nhẹ'**
  String get lookupSeverityMinor;

  /// Normalized severity label: caution
  ///
  /// In vi, this message translates to:
  /// **'Thận trọng'**
  String get lookupSeverityCaution;

  /// Normalized severity label: unknown
  ///
  /// In vi, this message translates to:
  /// **'Chưa xác định'**
  String get lookupSeverityUnknown;

  /// Error message when loading drug details fails
  ///
  /// In vi, this message translates to:
  /// **'Không tải được thông tin thuốc. Vui lòng thử lại.'**
  String get lookupErrorLoadDrugDetail;

  /// Error message when searching drugs fails
  ///
  /// In vi, this message translates to:
  /// **'Không thể tìm thuốc lúc này. Vui lòng thử lại.'**
  String get lookupErrorSearchDrugs;

  /// Validation error for minimum selected drugs
  ///
  /// In vi, this message translates to:
  /// **'Cần chọn ít nhất 2 thuốc để kiểm tra.'**
  String get lookupErrorMinDrugs;

  /// Validation error for minimum selected ingredients
  ///
  /// In vi, this message translates to:
  /// **'Cần chọn ít nhất 2 hoạt chất để kiểm tra.'**
  String get lookupErrorMinIngredients;

  /// Validation error for single ingredient input
  ///
  /// In vi, this message translates to:
  /// **'Nhập ít nhất 2 ký tự hoạt chất.'**
  String get lookupErrorMinSingleIngredient;

  /// Tooltip text for lookup tab alert badge
  ///
  /// In vi, this message translates to:
  /// **'Cảnh báo tương tác mức {severity}'**
  String lookupTabAlertTooltip(String severity);

  /// Bottom navigation label for Plan tab
  ///
  /// In vi, this message translates to:
  /// **'Kế hoạch'**
  String get navPlan;

  /// Bottom navigation label for History tab
  ///
  /// In vi, this message translates to:
  /// **'Lịch sử'**
  String get navHistory;

  /// Bottom navigation label for Settings tab
  ///
  /// In vi, this message translates to:
  /// **'Cài đặt'**
  String get navSettings;

  /// Generic loading state label
  ///
  /// In vi, this message translates to:
  /// **'Đang tải…'**
  String get commonLoading;

  /// Generic retry button label
  ///
  /// In vi, this message translates to:
  /// **'Thử lại'**
  String get commonRetry;

  /// Generic confirm button label
  ///
  /// In vi, this message translates to:
  /// **'Xác nhận'**
  String get commonConfirm;

  /// Generic cancel button label
  ///
  /// In vi, this message translates to:
  /// **'Hủy'**
  String get commonCancel;

  /// Generic save button label
  ///
  /// In vi, this message translates to:
  /// **'Lưu'**
  String get commonSave;

  /// Generic delete button label
  ///
  /// In vi, this message translates to:
  /// **'Xóa'**
  String get commonDelete;

  /// Generic edit button label
  ///
  /// In vi, this message translates to:
  /// **'Chỉnh sửa'**
  String get commonEdit;

  /// Generic close button label
  ///
  /// In vi, this message translates to:
  /// **'Đóng'**
  String get commonClose;

  /// Generic back button / navigation label
  ///
  /// In vi, this message translates to:
  /// **'Quay lại'**
  String get commonBack;

  /// Generic empty state message
  ///
  /// In vi, this message translates to:
  /// **'Không có dữ liệu'**
  String get commonEmptyState;

  /// Generic error message shown when no specific reason is available
  ///
  /// In vi, this message translates to:
  /// **'Đã xảy ra lỗi. Vui lòng thử lại.'**
  String get commonErrorGeneric;

  /// Network connectivity error message
  ///
  /// In vi, this message translates to:
  /// **'Không thể kết nối. Kiểm tra mạng và thử lại.'**
  String get commonErrorNetwork;

  /// Generic success message
  ///
  /// In vi, this message translates to:
  /// **'Thành công!'**
  String get commonSuccessGeneric;

  /// Generic acknowledgement button label
  ///
  /// In vi, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Android notification channel display name
  ///
  /// In vi, this message translates to:
  /// **'Nhắc uống thuốc'**
  String get notificationChannelName;

  /// Android notification channel description
  ///
  /// In vi, this message translates to:
  /// **'Thông báo nhắc nhở uống thuốc đúng giờ'**
  String get notificationChannelDescription;

  /// Default title for medication reminder notifications
  ///
  /// In vi, this message translates to:
  /// **'Đến giờ uống thuốc'**
  String get notificationDefaultTitle;

  /// Default body text for medication reminder notifications
  ///
  /// In vi, this message translates to:
  /// **'Hãy uống thuốc đúng giờ để đảm bảo hiệu quả điều trị.'**
  String get notificationDefaultBody;

  /// Title shown on 404/unknown route fallback screen
  ///
  /// In vi, this message translates to:
  /// **'Trang không tìm thấy'**
  String get routeFallbackTitle;

  /// No description provided for @authLoginTitle.
  ///
  /// In vi, this message translates to:
  /// **'Uống thuốc'**
  String get authLoginTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Quản lý đơn thuốc thông minh'**
  String get authLoginSubtitle;

  /// No description provided for @authEmailHint.
  ///
  /// In vi, this message translates to:
  /// **'Email'**
  String get authEmailHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In vi, this message translates to:
  /// **'Mật khẩu'**
  String get authPasswordHint;

  /// No description provided for @authLoginButton.
  ///
  /// In vi, this message translates to:
  /// **'Đăng nhập'**
  String get authLoginButton;

  /// No description provided for @authNoAccountPrompt.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có tài khoản? '**
  String get authNoAccountPrompt;

  /// No description provided for @authRegisterAction.
  ///
  /// In vi, this message translates to:
  /// **'Đăng ký'**
  String get authRegisterAction;

  /// No description provided for @authRegisterTitle.
  ///
  /// In vi, this message translates to:
  /// **'Tạo tài khoản'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Đăng ký để quản lý đơn thuốc'**
  String get authRegisterSubtitle;

  /// No description provided for @authNameOptionalHint.
  ///
  /// In vi, this message translates to:
  /// **'Họ tên (tùy chọn)'**
  String get authNameOptionalHint;

  /// No description provided for @authPasswordRequirements.
  ///
  /// In vi, this message translates to:
  /// **'Mật khẩu (≥8 ký tự, 1 hoa, 1 số)'**
  String get authPasswordRequirements;

  /// No description provided for @authPasswordConfirmHint.
  ///
  /// In vi, this message translates to:
  /// **'Xác nhận mật khẩu'**
  String get authPasswordConfirmHint;

  /// No description provided for @authRegisterButton.
  ///
  /// In vi, this message translates to:
  /// **'Đăng ký'**
  String get authRegisterButton;

  /// No description provided for @authHasAccountPrompt.
  ///
  /// In vi, this message translates to:
  /// **'Đã có tài khoản? '**
  String get authHasAccountPrompt;

  /// No description provided for @authLoginAction.
  ///
  /// In vi, this message translates to:
  /// **'Đăng nhập'**
  String get authLoginAction;

  /// No description provided for @authErrorEmptyEmailPassword.
  ///
  /// In vi, this message translates to:
  /// **'Vui lòng nhập email và mật khẩu'**
  String get authErrorEmptyEmailPassword;

  /// No description provided for @authErrorPasswordLength.
  ///
  /// In vi, this message translates to:
  /// **'Mật khẩu phải có ít nhất 8 ký tự'**
  String get authErrorPasswordLength;

  /// No description provided for @authErrorPasswordUppercase.
  ///
  /// In vi, this message translates to:
  /// **'Mật khẩu phải có ít nhất 1 chữ hoa'**
  String get authErrorPasswordUppercase;

  /// No description provided for @authErrorPasswordNumber.
  ///
  /// In vi, this message translates to:
  /// **'Mật khẩu phải có ít nhất 1 số'**
  String get authErrorPasswordNumber;

  /// No description provided for @authErrorPasswordMismatch.
  ///
  /// In vi, this message translates to:
  /// **'Mật khẩu xác nhận không khớp'**
  String get authErrorPasswordMismatch;

  /// No description provided for @authErrorLoginFailed.
  ///
  /// In vi, this message translates to:
  /// **'Đăng nhập thất bại'**
  String get authErrorLoginFailed;

  /// No description provided for @authErrorRegisterFailed.
  ///
  /// In vi, this message translates to:
  /// **'Đăng ký thất bại'**
  String get authErrorRegisterFailed;

  /// No description provided for @authErrorRegisterGeneric.
  ///
  /// In vi, this message translates to:
  /// **'Đã xảy ra lỗi khi đăng ký'**
  String get authErrorRegisterGeneric;

  /// No description provided for @authErrorLoginAfterRegister.
  ///
  /// In vi, this message translates to:
  /// **'Đăng ký xong nhưng đăng nhập thất bại'**
  String get authErrorLoginAfterRegister;

  /// No description provided for @authErrorTimeout.
  ///
  /// In vi, this message translates to:
  /// **'Kết nối quá chậm, thử lại sau'**
  String get authErrorTimeout;

  /// No description provided for @authErrorNoConnection.
  ///
  /// In vi, this message translates to:
  /// **'Không kết nối được máy chủ'**
  String get authErrorNoConnection;

  /// No description provided for @authErrorInvalidData.
  ///
  /// In vi, this message translates to:
  /// **'Thông tin không hợp lệ'**
  String get authErrorInvalidData;

  /// No description provided for @authErrorWrongCredentials.
  ///
  /// In vi, this message translates to:
  /// **'Email hoặc mật khẩu sai'**
  String get authErrorWrongCredentials;

  /// No description provided for @authErrorEmailExists.
  ///
  /// In vi, this message translates to:
  /// **'Email đã được đăng ký'**
  String get authErrorEmailExists;

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In vi, this message translates to:
  /// **'Quá nhiều yêu cầu, thử lại sau'**
  String get authErrorTooManyRequests;

  /// No description provided for @authErrorServerError.
  ///
  /// In vi, this message translates to:
  /// **'Server đang gặp sự cố'**
  String get authErrorServerError;

  /// No description provided for @authErrorUnknown.
  ///
  /// In vi, this message translates to:
  /// **'Đã xảy ra lỗi ({code})'**
  String authErrorUnknown(String code);

  /// No description provided for @homeSyncSuccess.
  ///
  /// In vi, this message translates to:
  /// **'Đã đồng bộ {count} thao tác offline'**
  String homeSyncSuccess(int count);

  /// No description provided for @homeErrorLoadToday.
  ///
  /// In vi, this message translates to:
  /// **'Không tải được dữ liệu hôm nay'**
  String get homeErrorLoadToday;

  /// No description provided for @homeOnboardingTitle.
  ///
  /// In vi, this message translates to:
  /// **'Bắt đầu quản lý thuốc một cách dễ hiểu'**
  String get homeOnboardingTitle;

  /// No description provided for @homeOnboardingSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Quét đơn thuốc để tạo lịch nhắc, hoặc nhập thủ công nếu bạn muốn bắt đầu ngay.'**
  String get homeOnboardingSubtitle;

  /// No description provided for @homeActionScan.
  ///
  /// In vi, this message translates to:
  /// **'Quét đơn thuốc mới'**
  String get homeActionScan;

  /// No description provided for @homeActionManual.
  ///
  /// In vi, this message translates to:
  /// **'Nhập tay'**
  String get homeActionManual;

  /// No description provided for @homeActionHistory.
  ///
  /// In vi, this message translates to:
  /// **'Lịch sử'**
  String get homeActionHistory;

  /// No description provided for @homeActionDrugLookup.
  ///
  /// In vi, this message translates to:
  /// **'Tra cứu thuốc'**
  String get homeActionDrugLookup;

  /// No description provided for @homeActionDrugLookupSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Xem thông tin thuốc và hoạt chất'**
  String get homeActionDrugLookupSubtitle;

  /// No description provided for @homeActionPlans.
  ///
  /// In vi, this message translates to:
  /// **'Kế hoạch'**
  String get homeActionPlans;

  /// No description provided for @homeActionPlansSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Xem các lịch đã tạo'**
  String get homeActionPlansSubtitle;

  /// No description provided for @homePendingSync.
  ///
  /// In vi, this message translates to:
  /// **'{count} thao tác đang chờ đồng bộ. Kéo xuống để đồng bộ lại.'**
  String homePendingSync(int count);

  /// No description provided for @homeTitleToday.
  ///
  /// In vi, this message translates to:
  /// **'Hôm nay'**
  String get homeTitleToday;

  /// No description provided for @homeTodayDrugs.
  ///
  /// In vi, this message translates to:
  /// **'Thuốc hôm nay'**
  String get homeTodayDrugs;

  /// No description provided for @homeHeroTitle.
  ///
  /// In vi, this message translates to:
  /// **'Theo dõi liều uống hôm nay'**
  String get homeHeroTitle;

  /// No description provided for @homeHeroTotalDoses.
  ///
  /// In vi, this message translates to:
  /// **'{count} liều cần quan tâm'**
  String homeHeroTotalDoses(int count);

  /// No description provided for @homeHeroTaken.
  ///
  /// In vi, this message translates to:
  /// **'Đã uống'**
  String get homeHeroTaken;

  /// No description provided for @homeHeroPending.
  ///
  /// In vi, this message translates to:
  /// **'Chờ'**
  String get homeHeroPending;

  /// No description provided for @homeHeroSkipped.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ qua'**
  String get homeHeroSkipped;

  /// No description provided for @homeHeroMissed.
  ///
  /// In vi, this message translates to:
  /// **'Không uống'**
  String get homeHeroMissed;

  /// No description provided for @homeDoseTakenStatus.
  ///
  /// In vi, this message translates to:
  /// **'Đã uống: {title}'**
  String homeDoseTakenStatus(String title);

  /// No description provided for @homeDoseOfflineStatus.
  ///
  /// In vi, this message translates to:
  /// **'Đã lưu tạm offline'**
  String get homeDoseOfflineStatus;

  /// No description provided for @homeDoseSkippedStatus.
  ///
  /// In vi, this message translates to:
  /// **'Đã bỏ qua: {title}'**
  String homeDoseSkippedStatus(String title);

  /// No description provided for @homeInUse.
  ///
  /// In vi, this message translates to:
  /// **'Đang sử dụng'**
  String get homeInUse;

  /// No description provided for @homeViewAllPlans.
  ///
  /// In vi, this message translates to:
  /// **'Xem {count} kế hoạch'**
  String homeViewAllPlans(int count);

  /// No description provided for @homePlanActive.
  ///
  /// In vi, this message translates to:
  /// **'Đang bật'**
  String get homePlanActive;

  /// No description provided for @homeFreqHourly.
  ///
  /// In vi, this message translates to:
  /// **'Theo từng giờ'**
  String get homeFreqHourly;

  /// No description provided for @homeFreqWeekly.
  ///
  /// In vi, this message translates to:
  /// **'Hàng tuần'**
  String get homeFreqWeekly;

  /// No description provided for @homeFreqDaily1.
  ///
  /// In vi, this message translates to:
  /// **'1 lần/ngày'**
  String get homeFreqDaily1;

  /// No description provided for @homeFreqDaily2.
  ///
  /// In vi, this message translates to:
  /// **'2 lần/ngày'**
  String get homeFreqDaily2;

  /// No description provided for @homeFreqDaily3.
  ///
  /// In vi, this message translates to:
  /// **'3 lần/ngày'**
  String get homeFreqDaily3;

  /// No description provided for @homeLoadingToday.
  ///
  /// In vi, this message translates to:
  /// **'Đang tải kế hoạch hôm nay...'**
  String get homeLoadingToday;

  /// No description provided for @homeErrorLoadSchedule.
  ///
  /// In vi, this message translates to:
  /// **'Không tải được lịch hôm nay'**
  String get homeErrorLoadSchedule;

  /// No description provided for @homeSectionDueNow.
  ///
  /// In vi, this message translates to:
  /// **'Đến giờ uống'**
  String get homeSectionDueNow;

  /// No description provided for @homeSectionUpcoming.
  ///
  /// In vi, this message translates to:
  /// **'Sắp tới trong ngày'**
  String get homeSectionUpcoming;

  /// No description provided for @createPlanTitle.
  ///
  /// In vi, this message translates to:
  /// **'Tạo kế hoạch'**
  String get createPlanTitle;

  /// No description provided for @createPlanStartTitle.
  ///
  /// In vi, this message translates to:
  /// **'Tạo lịch uống thuốc mới'**
  String get createPlanStartTitle;

  /// No description provided for @createPlanStartSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Chọn cách tạo lịch phù hợp nhất với bạn'**
  String get createPlanStartSubtitle;

  /// No description provided for @createPlanDisclaimer.
  ///
  /// In vi, this message translates to:
  /// **'Lưu ý: Bạn nhớ dò lại tên thuốc cho đúng trước khi lưu.'**
  String get createPlanDisclaimer;

  /// No description provided for @createPlanScanTitle.
  ///
  /// In vi, this message translates to:
  /// **'Chụp ảnh đơn thuốc'**
  String get createPlanScanTitle;

  /// No description provided for @createPlanScanSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Máy tự đọc tên thuốc & liều dùng từ hình chụp'**
  String get createPlanScanSubtitle;

  /// No description provided for @createPlanManualTitle.
  ///
  /// In vi, this message translates to:
  /// **'Tự nhập bằng tay'**
  String get createPlanManualTitle;

  /// No description provided for @createPlanManualSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Tự gõ tên thuốc và chọn giờ uống theo ý bạn'**
  String get createPlanManualSubtitle;

  /// No description provided for @createPlanHistoryTitle.
  ///
  /// In vi, this message translates to:
  /// **'Dùng lại đơn cũ'**
  String get createPlanHistoryTitle;

  /// No description provided for @createPlanHistorySubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Mở lại danh sách thuốc bạn đã từng chụp trước đây'**
  String get createPlanHistorySubtitle;

  /// AppBar / top-bar title on scan camera screen
  ///
  /// In vi, this message translates to:
  /// **'Chụp đơn thuốc'**
  String get scanCameraTitle;

  /// No description provided for @scanCameraClose.
  ///
  /// In vi, this message translates to:
  /// **'Đóng'**
  String get scanCameraClose;

  /// No description provided for @scanCameraGuide.
  ///
  /// In vi, this message translates to:
  /// **'Hướng dẫn'**
  String get scanCameraGuide;

  /// No description provided for @scanCameraHint.
  ///
  /// In vi, this message translates to:
  /// **'Đưa danh sách thuốc vào khung hình\nvà chạm màn hình để chụp'**
  String get scanCameraHint;

  /// No description provided for @scanCameraGallery.
  ///
  /// In vi, this message translates to:
  /// **'Thư viện'**
  String get scanCameraGallery;

  /// No description provided for @scanCameraManual.
  ///
  /// In vi, this message translates to:
  /// **'Nhập tay'**
  String get scanCameraManual;

  /// No description provided for @scanCameraInitializing.
  ///
  /// In vi, this message translates to:
  /// **'Đang khởi động camera...'**
  String get scanCameraInitializing;

  /// No description provided for @scanCameraPermissionDenied.
  ///
  /// In vi, this message translates to:
  /// **'Quyền camera bị từ chối. Vào Cài đặt để cấp quyền.'**
  String get scanCameraPermissionDenied;

  /// No description provided for @scanCameraUnavailable.
  ///
  /// In vi, this message translates to:
  /// **'Camera không khả dụng.'**
  String get scanCameraUnavailable;

  /// No description provided for @scanCameraUseGallery.
  ///
  /// In vi, this message translates to:
  /// **'Dùng Thư viện'**
  String get scanCameraUseGallery;

  /// No description provided for @scanCameraCaptureFailed.
  ///
  /// In vi, this message translates to:
  /// **'Chụp ảnh thất bại. Thử lại.'**
  String get scanCameraCaptureFailed;

  /// No description provided for @scanCameraFileTooLarge.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh quá lớn, vui lòng chọn ảnh < 10MB'**
  String get scanCameraFileTooLarge;

  /// No description provided for @scanCameraGalleryError.
  ///
  /// In vi, this message translates to:
  /// **'Không thể mở thư viện ảnh'**
  String get scanCameraGalleryError;

  /// No description provided for @scanCameraUploadingTitle.
  ///
  /// In vi, this message translates to:
  /// **'Đang trích xuất thông tin từ đơn thuốc...'**
  String get scanCameraUploadingTitle;

  /// No description provided for @scanCameraUploadingSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Quá trình này mất khoảng 10–20 giây'**
  String get scanCameraUploadingSubtitle;

  /// No description provided for @scanCameraNodrugFound.
  ///
  /// In vi, this message translates to:
  /// **'Không nhận diện được thuốc nào. Hãy thử lại hoặc nhập tay.'**
  String get scanCameraNodrugFound;

  /// No description provided for @scanCameraErrorGeneric.
  ///
  /// In vi, this message translates to:
  /// **'Đã xảy ra lỗi khi quét'**
  String get scanCameraErrorGeneric;

  /// No description provided for @scanCameraErrorUnavailable.
  ///
  /// In vi, this message translates to:
  /// **'Dịch vụ AI tạm thời không khả dụng'**
  String get scanCameraErrorUnavailable;

  /// No description provided for @scanCameraErrorTimeout.
  ///
  /// In vi, this message translates to:
  /// **'Quá thời gian chờ, vui lòng thử lại'**
  String get scanCameraErrorTimeout;

  /// No description provided for @scanCameraErrorConnection.
  ///
  /// In vi, this message translates to:
  /// **'Không kết nối được máy chủ'**
  String get scanCameraErrorConnection;

  /// No description provided for @scanCameraQualityReject.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh có vấn đề, hãy chụp lại.'**
  String get scanCameraQualityReject;

  /// No description provided for @scanCameraQualityWarning.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh chưa tối ưu.'**
  String get scanCameraQualityWarning;

  /// No description provided for @scanCameraQualityDefault.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh có thể ảnh hưởng đến kết quả nhận diện.'**
  String get scanCameraQualityDefault;

  /// No description provided for @scanCameraRetake.
  ///
  /// In vi, this message translates to:
  /// **'Chụp lại'**
  String get scanCameraRetake;

  /// No description provided for @scanCameraProceed.
  ///
  /// In vi, this message translates to:
  /// **'Vẫn tiếp tục quét'**
  String get scanCameraProceed;

  /// No description provided for @scanCameraQualityBlurry.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh bị mờ'**
  String get scanCameraQualityBlurry;

  /// No description provided for @scanCameraQualityGlare.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh bị chói'**
  String get scanCameraQualityGlare;

  /// No description provided for @scanCameraQualityCutoff.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh bị cắt thiếu'**
  String get scanCameraQualityCutoff;

  /// No description provided for @scanCameraQualityUnknown.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh chưa đủ sắc nét'**
  String get scanCameraQualityUnknown;

  /// No description provided for @scanCameraGuideTitle.
  ///
  /// In vi, this message translates to:
  /// **'Hướng dẫn quét đơn thuốc'**
  String get scanCameraGuideTitle;

  /// No description provided for @scanCameraGuideStep1.
  ///
  /// In vi, this message translates to:
  /// **'1. Đưa vùng hiển thị tên thuốc vào giữa khung hình.'**
  String get scanCameraGuideStep1;

  /// No description provided for @scanCameraGuideStep2.
  ///
  /// In vi, this message translates to:
  /// **'2. Giữ máy ổn định, tránh chỗ quá chói sáng.'**
  String get scanCameraGuideStep2;

  /// No description provided for @scanCameraGuideStep3.
  ///
  /// In vi, this message translates to:
  /// **'3. Ứng dụng sẽ TỰ ĐỘNG CHỤP khi ảnh đủ rõ nét.'**
  String get scanCameraGuideStep3;

  /// No description provided for @scanCameraGuideStep4.
  ///
  /// In vi, this message translates to:
  /// **'4. Hoặc bạn có thể chạm vào màn hình / bấm nút để tự chụp.'**
  String get scanCameraGuideStep4;

  /// No description provided for @scanCameraQualityServerReject.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh có vấn đề, thử chụp lại rõ hơn.'**
  String get scanCameraQualityServerReject;

  /// No description provided for @scanReviewTitle.
  ///
  /// In vi, this message translates to:
  /// **'Xác nhận kết quả quét'**
  String get scanReviewTitle;

  /// No description provided for @scanReviewDefaultGuidance.
  ///
  /// In vi, this message translates to:
  /// **'Kiểm tra danh sách thuốc trước khi lập lịch.'**
  String get scanReviewDefaultGuidance;

  /// No description provided for @scanReviewDrugCount.
  ///
  /// In vi, this message translates to:
  /// **'{count} thuốc'**
  String scanReviewDrugCount(int count);

  /// No description provided for @scanReviewSearchHint.
  ///
  /// In vi, this message translates to:
  /// **'Tìm theo tên thuốc...'**
  String get scanReviewSearchHint;

  /// No description provided for @scanReviewEmptyFilter.
  ///
  /// In vi, this message translates to:
  /// **'Không có thuốc nào khớp với bộ lọc hiện tại'**
  String get scanReviewEmptyFilter;

  /// No description provided for @scanReviewStandardName.
  ///
  /// In vi, this message translates to:
  /// **'Tên chuẩn: {name}'**
  String scanReviewStandardName(String name);

  /// No description provided for @scanReviewOcrRaw.
  ///
  /// In vi, this message translates to:
  /// **'OCR gốc: {text}'**
  String scanReviewOcrRaw(String text);

  /// No description provided for @scanReviewEdit.
  ///
  /// In vi, this message translates to:
  /// **'Sửa'**
  String get scanReviewEdit;

  /// No description provided for @scanReviewRemove.
  ///
  /// In vi, this message translates to:
  /// **'Loại bỏ'**
  String get scanReviewRemove;

  /// No description provided for @scanReviewAddDrug.
  ///
  /// In vi, this message translates to:
  /// **'Thêm thuốc'**
  String get scanReviewAddDrug;

  /// No description provided for @scanReviewRescan.
  ///
  /// In vi, this message translates to:
  /// **'Quét lại'**
  String get scanReviewRescan;

  /// No description provided for @scanReviewContinue.
  ///
  /// In vi, this message translates to:
  /// **'Tiếp tục lập lịch ({count} thuốc)'**
  String scanReviewContinue(int count);

  /// No description provided for @editDrugsTitle.
  ///
  /// In vi, this message translates to:
  /// **'Danh sách thuốc'**
  String get editDrugsTitle;

  /// No description provided for @editDrugsAddTooltip.
  ///
  /// In vi, this message translates to:
  /// **'Thêm thuốc'**
  String get editDrugsAddTooltip;

  /// No description provided for @editDrugsEmptyTitle.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có thuốc nào'**
  String get editDrugsEmptyTitle;

  /// No description provided for @editDrugsEmptyHint.
  ///
  /// In vi, this message translates to:
  /// **'Bấm + để thêm thuốc'**
  String get editDrugsEmptyHint;

  /// No description provided for @editDrugsEmptyAddFirst.
  ///
  /// In vi, this message translates to:
  /// **'Thêm thuốc đầu tiên'**
  String get editDrugsEmptyAddFirst;

  /// No description provided for @editDrugsContinue.
  ///
  /// In vi, this message translates to:
  /// **'Tiếp tục — {count} thuốc'**
  String editDrugsContinue(int count);

  /// No description provided for @scheduleTitle.
  ///
  /// In vi, this message translates to:
  /// **'Thiết lập giờ uống thuốc'**
  String get scheduleTitle;

  /// No description provided for @scheduleHeaderTitle.
  ///
  /// In vi, this message translates to:
  /// **'Thiết lập giờ uống'**
  String get scheduleHeaderTitle;

  /// No description provided for @scheduleHeaderSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Chọn số lần uống mỗi ngày trước, rồi chỉnh lại nếu cần.'**
  String get scheduleHeaderSubtitle;

  /// No description provided for @scheduleDateRangeLabel.
  ///
  /// In vi, this message translates to:
  /// **'Thời gian dùng thuốc'**
  String get scheduleDateRangeLabel;

  /// No description provided for @scheduleDateStart.
  ///
  /// In vi, this message translates to:
  /// **'Bắt đầu'**
  String get scheduleDateStart;

  /// No description provided for @scheduleDateEnd.
  ///
  /// In vi, this message translates to:
  /// **'Kết thúc'**
  String get scheduleDateEnd;

  /// No description provided for @scheduleDateSummary.
  ///
  /// In vi, this message translates to:
  /// **'Tổng {days} ngày · từ {start} đến {end}'**
  String scheduleDateSummary(int days, String start, String end);

  /// No description provided for @schedulePresetLabel.
  ///
  /// In vi, this message translates to:
  /// **'1) Chọn nhanh số lần uống mỗi ngày'**
  String get schedulePresetLabel;

  /// No description provided for @schedulePresetHint.
  ///
  /// In vi, this message translates to:
  /// **'Bạn chỉ cần chọn một mức phù hợp. Có thể chỉnh giờ chi tiết ở bên dưới.'**
  String get schedulePresetHint;

  /// No description provided for @schedulePreset1.
  ///
  /// In vi, this message translates to:
  /// **'1 lần/ngày'**
  String get schedulePreset1;

  /// No description provided for @schedulePreset2.
  ///
  /// In vi, this message translates to:
  /// **'2 lần/ngày'**
  String get schedulePreset2;

  /// No description provided for @schedulePreset3.
  ///
  /// In vi, this message translates to:
  /// **'3 lần/ngày'**
  String get schedulePreset3;

  /// No description provided for @scheduleSlotsLabel.
  ///
  /// In vi, this message translates to:
  /// **'2) Giờ uống thuốc (chỉnh thêm nếu cần)'**
  String get scheduleSlotsLabel;

  /// No description provided for @scheduleAddSlot.
  ///
  /// In vi, this message translates to:
  /// **'Thêm giờ uống khác'**
  String get scheduleAddSlot;

  /// No description provided for @schedulePillsLabel.
  ///
  /// In vi, this message translates to:
  /// **'3) Số viên ở từng giờ uống'**
  String get schedulePillsLabel;

  /// No description provided for @schedulePillsHint.
  ///
  /// In vi, this message translates to:
  /// **'Bạn có thể đặt số viên khác nhau cho từng giờ của cùng một thuốc.'**
  String get schedulePillsHint;

  /// No description provided for @scheduleSlotNoDrug.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có thuốc nào ở giờ này.'**
  String get scheduleSlotNoDrug;

  /// No description provided for @scheduleReviewLabel.
  ///
  /// In vi, this message translates to:
  /// **'4) Xem lại trước khi lưu'**
  String get scheduleReviewLabel;

  /// No description provided for @scheduleSave.
  ///
  /// In vi, this message translates to:
  /// **'Lưu kế hoạch'**
  String get scheduleSave;

  /// No description provided for @scheduleSaveSuccess.
  ///
  /// In vi, this message translates to:
  /// **'Đã tạo kế hoạch uống thuốc'**
  String get scheduleSaveSuccess;

  /// No description provided for @scheduleSaveErrorConnection.
  ///
  /// In vi, this message translates to:
  /// **'Không kết nối được máy chủ'**
  String get scheduleSaveErrorConnection;

  /// No description provided for @scheduleSaveErrorSession.
  ///
  /// In vi, this message translates to:
  /// **'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.'**
  String get scheduleSaveErrorSession;

  /// No description provided for @scheduleSaveErrorGeneric.
  ///
  /// In vi, this message translates to:
  /// **'Không thể lưu kế hoạch'**
  String get scheduleSaveErrorGeneric;

  /// No description provided for @scheduleSaveErrorUnknown.
  ///
  /// In vi, this message translates to:
  /// **'Lỗi: {error}'**
  String scheduleSaveErrorUnknown(String error);

  /// No description provided for @scheduleSlotNoSelection.
  ///
  /// In vi, this message translates to:
  /// **'Chưa chọn thuốc cho giờ này'**
  String get scheduleSlotNoSelection;

  /// No description provided for @scheduleSlotDrugPreview.
  ///
  /// In vi, this message translates to:
  /// **'Thuốc: {names}'**
  String scheduleSlotDrugPreview(String names);

  /// No description provided for @scheduleSlotDrugPreviewMore.
  ///
  /// In vi, this message translates to:
  /// **'Thuốc: {names} và {count} thuốc khác'**
  String scheduleSlotDrugPreviewMore(String names, int count);

  /// No description provided for @scheduleSlotDrugCount.
  ///
  /// In vi, this message translates to:
  /// **'{count} thuốc'**
  String scheduleSlotDrugCount(int count);

  /// No description provided for @scheduleSlotChooseDrug.
  ///
  /// In vi, this message translates to:
  /// **'Chọn thuốc uống ở giờ này:'**
  String get scheduleSlotChooseDrug;

  /// No description provided for @scheduleSlotRemoveTooltip.
  ///
  /// In vi, this message translates to:
  /// **'Xóa khung giờ'**
  String get scheduleSlotRemoveTooltip;

  /// No description provided for @schedulePlanTitleSingle.
  ///
  /// In vi, this message translates to:
  /// **'{name}'**
  String schedulePlanTitleSingle(String name);

  /// No description provided for @schedulePlanTitleMultiple.
  ///
  /// In vi, this message translates to:
  /// **'{first} và {rest} thuốc khác'**
  String schedulePlanTitleMultiple(String first, int rest);

  /// No description provided for @schedulePlanTitleDefault.
  ///
  /// In vi, this message translates to:
  /// **'Kế hoạch thuốc'**
  String get schedulePlanTitleDefault;

  /// No description provided for @scheduleSummaryDose.
  ///
  /// In vi, this message translates to:
  /// **'{time}: {pills} viên'**
  String scheduleSummaryDose(String time, int pills);

  /// No description provided for @scheduleSummaryLine.
  ///
  /// In vi, this message translates to:
  /// **'{drugName}: {summary}'**
  String scheduleSummaryLine(String drugName, String summary);

  /// No description provided for @drugEntrySheetAddTitle.
  ///
  /// In vi, this message translates to:
  /// **'Thêm thuốc'**
  String get drugEntrySheetAddTitle;

  /// No description provided for @drugEntrySheetEditTitle.
  ///
  /// In vi, this message translates to:
  /// **'Sửa thuốc'**
  String get drugEntrySheetEditTitle;

  /// No description provided for @drugEntrySheetNameLabel.
  ///
  /// In vi, this message translates to:
  /// **'Tên thuốc *'**
  String get drugEntrySheetNameLabel;

  /// No description provided for @drugEntrySheetNameHint.
  ///
  /// In vi, this message translates to:
  /// **'Nhập ít nhất 2 ký tự để tìm gợi ý...'**
  String get drugEntrySheetNameHint;

  /// No description provided for @drugEntrySheetDosageLabel.
  ///
  /// In vi, this message translates to:
  /// **'Liều lượng (tuỳ chọn)'**
  String get drugEntrySheetDosageLabel;

  /// No description provided for @drugEntrySheetDosageHint.
  ///
  /// In vi, this message translates to:
  /// **'VD: 500mg'**
  String get drugEntrySheetDosageHint;

  /// No description provided for @drugEntrySheetCancel.
  ///
  /// In vi, this message translates to:
  /// **'Huỷ'**
  String get drugEntrySheetCancel;

  /// No description provided for @drugEntrySheetAdd.
  ///
  /// In vi, this message translates to:
  /// **'Thêm'**
  String get drugEntrySheetAdd;

  /// No description provided for @drugEntrySheetSave.
  ///
  /// In vi, this message translates to:
  /// **'Lưu'**
  String get drugEntrySheetSave;

  /// No description provided for @drugEntrySheetSearching.
  ///
  /// In vi, this message translates to:
  /// **'Đang tìm gợi ý...'**
  String get drugEntrySheetSearching;

  /// No description provided for @drugEntrySheetPillsPerDoseLabel.
  ///
  /// In vi, this message translates to:
  /// **'Số viên/lần'**
  String get drugEntrySheetPillsPerDoseLabel;

  /// No description provided for @drugEntrySheetTotalDaysLabel.
  ///
  /// In vi, this message translates to:
  /// **'Số ngày uống'**
  String get drugEntrySheetTotalDaysLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

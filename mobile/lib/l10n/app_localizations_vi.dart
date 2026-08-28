// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'Uống thuốc';

  @override
  String get navHome => 'Trang chủ';

  @override
  String get navCreatePlan => 'Tạo kế hoạch';

  @override
  String get navDrug => 'Thuốc';

  @override
  String get navLookup => 'Tra cứu';

  @override
  String get lookupTitle => 'Tra cứu';

  @override
  String get lookupSectionDrugs => 'Thuốc';

  @override
  String get lookupSectionInteractions => 'Tương tác';

  @override
  String get lookupSectionIngredients => 'Hoạt chất';

  @override
  String get lookupDrugSectionTitle => 'Tra cứu thuốc';

  @override
  String get lookupDrugSectionSubtitle =>
      'Tìm theo tên thương mại hoặc hoạt chất để xem thông tin chi tiết.';

  @override
  String get lookupDrugSearchHint => 'Ví dụ: Paracetamol, Hapacol...';

  @override
  String get lookupInteractionSectionTitle => 'Kiểm tra tương tác theo thuốc';

  @override
  String get lookupInteractionSectionSubtitle =>
      'Chọn từ 2 thuốc trở lên để kiểm tra các cặp có nguy cơ tương tác.';

  @override
  String get lookupInteractionDrugSearchHint => 'Nhập tên thuốc để thêm...';

  @override
  String get lookupIngredientsSectionTitle =>
      'Kiểm tra theo danh sách hoạt chất';

  @override
  String get lookupIngredientsSectionSubtitle =>
      'Thêm hoạt chất trực tiếp để kiểm tra tương tác dược lý.';

  @override
  String get lookupIngredientSearchHint =>
      'Nhập hoạt chất (ví dụ: Paracetamol)';

  @override
  String get lookupSingleIngredientTitle => 'Tra cứu 1 hoạt chất';

  @override
  String get lookupSingleIngredientSubtitle =>
      'Xem toàn bộ tương tác liên quan tới một hoạt chất cụ thể.';

  @override
  String get lookupSingleIngredientHint => 'Ví dụ: Levocetirizine';

  @override
  String get lookupActionCheckInteractions => 'Kiểm tra tương tác';

  @override
  String get lookupActionCheckByIngredients => 'Kiểm tra theo hoạt chất';

  @override
  String get lookupActionLookupIngredient => 'Tra cứu hoạt chất';

  @override
  String get lookupActionClearSelection => 'Xóa chọn';

  @override
  String get lookupHintEnterAtLeast2Chars =>
      'Nhập ít nhất 2 ký tự để bắt đầu tra cứu thuốc.';

  @override
  String get lookupHintNoDrugResult =>
      'Không tìm thấy thuốc phù hợp với từ khóa hiện tại.';

  @override
  String get lookupHintNoSelectedDrugs => 'Chưa chọn thuốc nào.';

  @override
  String get lookupHintNoSelectedIngredients => 'Chưa chọn hoạt chất nào.';

  @override
  String get lookupUnknownIngredient => 'Không rõ hoạt chất';

  @override
  String get lookupIngredientSuggestionLabel => 'Hoạt chất gợi ý';

  @override
  String get lookupResultByDrugsTitle => 'Kết quả tương tác theo thuốc';

  @override
  String get lookupResultByIngredientsTitle =>
      'Kết quả theo danh sách hoạt chất';

  @override
  String get lookupResultBySingleIngredientTitle =>
      'Kết quả theo một hoạt chất';

  @override
  String get lookupNoInteractions =>
      'Chưa ghi nhận tương tác trong dữ liệu hiện tại.';

  @override
  String lookupSummaryTotal(int count) {
    return 'Tổng: $count';
  }

  @override
  String lookupGroupPairCount(int count) {
    return '$count cặp';
  }

  @override
  String get lookupUnknownInteractionPair => 'Cặp tương tác chưa xác định';

  @override
  String get lookupSeverityContraindicated => 'Chống chỉ định';

  @override
  String get lookupSeverityMajor => 'Nghiêm trọng';

  @override
  String get lookupSeverityModerate => 'Trung bình';

  @override
  String get lookupSeverityMinor => 'Nhẹ';

  @override
  String get lookupSeverityCaution => 'Thận trọng';

  @override
  String get lookupSeverityUnknown => 'Chưa xác định';

  @override
  String get lookupErrorLoadDrugDetail =>
      'Không tải được thông tin thuốc. Vui lòng thử lại.';

  @override
  String get lookupErrorSearchDrugs =>
      'Không thể tìm thuốc lúc này. Vui lòng thử lại.';

  @override
  String get lookupErrorMinDrugs => 'Cần chọn ít nhất 2 thuốc để kiểm tra.';

  @override
  String get lookupErrorMinIngredients =>
      'Cần chọn ít nhất 2 hoạt chất để kiểm tra.';

  @override
  String get lookupErrorMinSingleIngredient =>
      'Nhập ít nhất 2 ký tự hoạt chất.';

  @override
  String lookupTabAlertTooltip(String severity) {
    return 'Cảnh báo tương tác mức $severity';
  }

  @override
  String get navPlan => 'Kế hoạch';

  @override
  String get navHistory => 'Lịch sử';

  @override
  String get navSettings => 'Cài đặt';

  @override
  String get commonLoading => 'Đang tải…';

  @override
  String get commonRetry => 'Thử lại';

  @override
  String get commonConfirm => 'Xác nhận';

  @override
  String get commonCancel => 'Hủy';

  @override
  String get commonSave => 'Lưu';

  @override
  String get commonDelete => 'Xóa';

  @override
  String get commonEdit => 'Chỉnh sửa';

  @override
  String get commonClose => 'Đóng';

  @override
  String get commonBack => 'Quay lại';

  @override
  String get commonEmptyState => 'Không có dữ liệu';

  @override
  String get commonErrorGeneric => 'Đã xảy ra lỗi. Vui lòng thử lại.';

  @override
  String get commonErrorNetwork =>
      'Không thể kết nối. Kiểm tra mạng và thử lại.';

  @override
  String get commonSuccessGeneric => 'Thành công!';

  @override
  String get commonOk => 'OK';

  @override
  String get notificationChannelName => 'Nhắc uống thuốc';

  @override
  String get notificationChannelDescription =>
      'Thông báo nhắc nhở uống thuốc đúng giờ';

  @override
  String get notificationDefaultTitle => 'Đến giờ uống thuốc';

  @override
  String get notificationDefaultBody =>
      'Hãy uống thuốc đúng giờ để đảm bảo hiệu quả điều trị.';

  @override
  String get routeFallbackTitle => 'Trang không tìm thấy';

  @override
  String get authLoginTitle => 'Uống thuốc';

  @override
  String get authLoginSubtitle => 'Quản lý đơn thuốc thông minh';

  @override
  String get authEmailHint => 'Email';

  @override
  String get authPasswordHint => 'Mật khẩu';

  @override
  String get authLoginButton => 'Đăng nhập';

  @override
  String get authNoAccountPrompt => 'Chưa có tài khoản? ';

  @override
  String get authRegisterAction => 'Đăng ký';

  @override
  String get authRegisterTitle => 'Tạo tài khoản';

  @override
  String get authRegisterSubtitle => 'Đăng ký để quản lý đơn thuốc';

  @override
  String get authNameOptionalHint => 'Họ tên (tùy chọn)';

  @override
  String get authPasswordRequirements => 'Mật khẩu (≥8 ký tự, 1 hoa, 1 số)';

  @override
  String get authPasswordConfirmHint => 'Xác nhận mật khẩu';

  @override
  String get authRegisterButton => 'Đăng ký';

  @override
  String get authHasAccountPrompt => 'Đã có tài khoản? ';

  @override
  String get authLoginAction => 'Đăng nhập';

  @override
  String get authErrorEmptyEmailPassword => 'Vui lòng nhập email và mật khẩu';

  @override
  String get authErrorPasswordLength => 'Mật khẩu phải có ít nhất 8 ký tự';

  @override
  String get authErrorPasswordUppercase => 'Mật khẩu phải có ít nhất 1 chữ hoa';

  @override
  String get authErrorPasswordNumber => 'Mật khẩu phải có ít nhất 1 số';

  @override
  String get authErrorPasswordMismatch => 'Mật khẩu xác nhận không khớp';

  @override
  String get authErrorLoginFailed => 'Đăng nhập thất bại';

  @override
  String get authErrorRegisterFailed => 'Đăng ký thất bại';

  @override
  String get authErrorRegisterGeneric => 'Đã xảy ra lỗi khi đăng ký';

  @override
  String get authErrorLoginAfterRegister =>
      'Đăng ký xong nhưng đăng nhập thất bại';

  @override
  String get authErrorTimeout => 'Kết nối quá chậm, thử lại sau';

  @override
  String get authErrorNoConnection => 'Không kết nối được máy chủ';

  @override
  String get authErrorInvalidData => 'Thông tin không hợp lệ';

  @override
  String get authErrorWrongCredentials => 'Email hoặc mật khẩu sai';

  @override
  String get authErrorEmailExists => 'Email đã được đăng ký';

  @override
  String get authErrorTooManyRequests => 'Quá nhiều yêu cầu, thử lại sau';

  @override
  String get authErrorServerError => 'Server đang gặp sự cố';

  @override
  String authErrorUnknown(String code) {
    return 'Đã xảy ra lỗi ($code)';
  }

  @override
  String homeSyncSuccess(int count) {
    return 'Đã đồng bộ $count thao tác offline';
  }

  @override
  String get homeErrorLoadToday => 'Không tải được dữ liệu hôm nay';

  @override
  String get homeOnboardingTitle => 'Bắt đầu quản lý thuốc một cách dễ hiểu';

  @override
  String get homeOnboardingSubtitle =>
      'Quét đơn thuốc để tạo lịch nhắc, hoặc nhập thủ công nếu bạn muốn bắt đầu ngay.';

  @override
  String get homeActionScan => 'Quét đơn thuốc mới';

  @override
  String get homeActionManual => 'Nhập tay';

  @override
  String get homeActionHistory => 'Lịch sử';

  @override
  String get homeActionDrugLookup => 'Tra cứu thuốc';

  @override
  String get homeActionDrugLookupSubtitle => 'Xem thông tin thuốc và hoạt chất';

  @override
  String get homeActionPlans => 'Kế hoạch';

  @override
  String get homeActionPlansSubtitle => 'Xem các lịch đã tạo';

  @override
  String homePendingSync(int count) {
    return '$count thao tác đang chờ đồng bộ. Kéo xuống để đồng bộ lại.';
  }

  @override
  String get homeTitleToday => 'Hôm nay';

  @override
  String get homeTodayDrugs => 'Thuốc hôm nay';

  @override
  String get homeHeroTitle => 'Theo dõi liều uống hôm nay';

  @override
  String homeHeroTotalDoses(int count) {
    return '$count liều cần quan tâm';
  }

  @override
  String get homeHeroTaken => 'Đã uống';

  @override
  String get homeHeroPending => 'Chờ';

  @override
  String get homeHeroSkipped => 'Bỏ qua';

  @override
  String get homeHeroMissed => 'Không uống';

  @override
  String homeDoseTakenStatus(String title) {
    return 'Đã uống: $title';
  }

  @override
  String get homeDoseOfflineStatus => 'Đã lưu tạm offline';

  @override
  String homeDoseSkippedStatus(String title) {
    return 'Đã bỏ qua: $title';
  }

  @override
  String get homeInUse => 'Đang sử dụng';

  @override
  String homeViewAllPlans(int count) {
    return 'Xem $count kế hoạch';
  }

  @override
  String get homePlanActive => 'Đang bật';

  @override
  String get homeFreqHourly => 'Theo từng giờ';

  @override
  String get homeFreqWeekly => 'Hàng tuần';

  @override
  String get homeFreqDaily1 => '1 lần/ngày';

  @override
  String get homeFreqDaily2 => '2 lần/ngày';

  @override
  String get homeFreqDaily3 => '3 lần/ngày';

  @override
  String get homeLoadingToday => 'Đang tải kế hoạch hôm nay...';

  @override
  String get homeErrorLoadSchedule => 'Không tải được lịch hôm nay';

  @override
  String get homeSectionDueNow => 'Đến giờ uống';

  @override
  String get homeSectionUpcoming => 'Sắp tới trong ngày';

  @override
  String get createPlanTitle => 'Tạo kế hoạch';

  @override
  String get createPlanStartTitle => 'Tạo lịch uống thuốc mới';

  @override
  String get createPlanStartSubtitle =>
      'Chọn cách tạo lịch phù hợp nhất với bạn';

  @override
  String get createPlanDisclaimer =>
      'Lưu ý: Bạn nhớ dò lại tên thuốc cho đúng trước khi lưu.';

  @override
  String get createPlanScanTitle => 'Chụp ảnh đơn thuốc';

  @override
  String get createPlanScanSubtitle =>
      'Máy tự đọc tên thuốc & liều dùng từ hình chụp';

  @override
  String get createPlanManualTitle => 'Tự nhập bằng tay';

  @override
  String get createPlanManualSubtitle =>
      'Tự gõ tên thuốc và chọn giờ uống theo ý bạn';

  @override
  String get createPlanHistoryTitle => 'Dùng lại đơn cũ';

  @override
  String get createPlanHistorySubtitle =>
      'Mở lại danh sách thuốc bạn đã từng chụp trước đây';

  @override
  String get scanCameraTitle => 'Chụp đơn thuốc';

  @override
  String get scanCameraClose => 'Đóng';

  @override
  String get scanCameraGuide => 'Hướng dẫn';

  @override
  String get scanCameraHint =>
      'Đưa danh sách thuốc vào khung hình\nvà chạm màn hình để chụp';

  @override
  String get scanCameraGallery => 'Thư viện';

  @override
  String get scanCameraManual => 'Nhập tay';

  @override
  String get scanCameraInitializing => 'Đang khởi động camera...';

  @override
  String get scanCameraPermissionDenied =>
      'Quyền camera bị từ chối. Vào Cài đặt để cấp quyền.';

  @override
  String get scanCameraUnavailable => 'Camera không khả dụng.';

  @override
  String get scanCameraUseGallery => 'Dùng Thư viện';

  @override
  String get scanCameraCaptureFailed => 'Chụp ảnh thất bại. Thử lại.';

  @override
  String get scanCameraFileTooLarge => 'Ảnh quá lớn, vui lòng chọn ảnh < 10MB';

  @override
  String get scanCameraGalleryError => 'Không thể mở thư viện ảnh';

  @override
  String get scanCameraUploadingTitle =>
      'Đang trích xuất thông tin từ đơn thuốc...';

  @override
  String get scanCameraUploadingSubtitle =>
      'Quá trình này mất khoảng 10–20 giây';

  @override
  String get scanCameraNodrugFound =>
      'Không nhận diện được thuốc nào. Hãy thử lại hoặc nhập tay.';

  @override
  String get scanCameraErrorGeneric => 'Đã xảy ra lỗi khi quét';

  @override
  String get scanCameraErrorUnavailable => 'Dịch vụ AI tạm thời không khả dụng';

  @override
  String get scanCameraErrorTimeout => 'Quá thời gian chờ, vui lòng thử lại';

  @override
  String get scanCameraErrorConnection => 'Không kết nối được máy chủ';

  @override
  String get scanCameraQualityReject => 'Ảnh có vấn đề, hãy chụp lại.';

  @override
  String get scanCameraQualityWarning => 'Ảnh chưa tối ưu.';

  @override
  String get scanCameraQualityDefault =>
      'Ảnh có thể ảnh hưởng đến kết quả nhận diện.';

  @override
  String get scanCameraRetake => 'Chụp lại';

  @override
  String get scanCameraProceed => 'Vẫn tiếp tục quét';

  @override
  String get scanCameraQualityBlurry => 'Ảnh bị mờ';

  @override
  String get scanCameraQualityGlare => 'Ảnh bị chói';

  @override
  String get scanCameraQualityCutoff => 'Ảnh bị cắt thiếu';

  @override
  String get scanCameraQualityUnknown => 'Ảnh chưa đủ sắc nét';

  @override
  String get scanCameraGuideTitle => 'Hướng dẫn quét đơn thuốc';

  @override
  String get scanCameraGuideStep1 =>
      '1. Đưa vùng hiển thị tên thuốc vào giữa khung hình.';

  @override
  String get scanCameraGuideStep2 =>
      '2. Giữ máy ổn định, tránh chỗ quá chói sáng.';

  @override
  String get scanCameraGuideStep3 =>
      '3. Ứng dụng sẽ TỰ ĐỘNG CHỤP khi ảnh đủ rõ nét.';

  @override
  String get scanCameraGuideStep4 =>
      '4. Hoặc bạn có thể chạm vào màn hình / bấm nút để tự chụp.';

  @override
  String get scanCameraQualityServerReject =>
      'Ảnh có vấn đề, thử chụp lại rõ hơn.';

  @override
  String get scanReviewTitle => 'Xác nhận kết quả quét';

  @override
  String get scanReviewDefaultGuidance =>
      'Kiểm tra danh sách thuốc trước khi lập lịch.';

  @override
  String scanReviewDrugCount(int count) {
    return '$count thuốc';
  }

  @override
  String get scanReviewSearchHint => 'Tìm theo tên thuốc...';

  @override
  String get scanReviewEmptyFilter =>
      'Không có thuốc nào khớp với bộ lọc hiện tại';

  @override
  String scanReviewStandardName(String name) {
    return 'Tên chuẩn: $name';
  }

  @override
  String scanReviewOcrRaw(String text) {
    return 'OCR gốc: $text';
  }

  @override
  String get scanReviewEdit => 'Sửa';

  @override
  String get scanReviewRemove => 'Loại bỏ';

  @override
  String get scanReviewAddDrug => 'Thêm thuốc';

  @override
  String get scanReviewRescan => 'Quét lại';

  @override
  String scanReviewContinue(int count) {
    return 'Tiếp tục lập lịch ($count thuốc)';
  }

  @override
  String get editDrugsTitle => 'Danh sách thuốc';

  @override
  String get editDrugsAddTooltip => 'Thêm thuốc';

  @override
  String get editDrugsEmptyTitle => 'Chưa có thuốc nào';

  @override
  String get editDrugsEmptyHint => 'Bấm + để thêm thuốc';

  @override
  String get editDrugsEmptyAddFirst => 'Thêm thuốc đầu tiên';

  @override
  String editDrugsContinue(int count) {
    return 'Tiếp tục — $count thuốc';
  }

  @override
  String get scheduleTitle => 'Thiết lập giờ uống thuốc';

  @override
  String get scheduleHeaderTitle => 'Thiết lập giờ uống';

  @override
  String get scheduleHeaderSubtitle =>
      'Chọn số lần uống mỗi ngày trước, rồi chỉnh lại nếu cần.';

  @override
  String get scheduleDateRangeLabel => 'Thời gian dùng thuốc';

  @override
  String get scheduleDateStart => 'Bắt đầu';

  @override
  String get scheduleDateEnd => 'Kết thúc';

  @override
  String scheduleDateSummary(int days, String start, String end) {
    return 'Tổng $days ngày · từ $start đến $end';
  }

  @override
  String get schedulePresetLabel => '1) Chọn nhanh số lần uống mỗi ngày';

  @override
  String get schedulePresetHint =>
      'Bạn chỉ cần chọn một mức phù hợp. Có thể chỉnh giờ chi tiết ở bên dưới.';

  @override
  String get schedulePreset1 => '1 lần/ngày';

  @override
  String get schedulePreset2 => '2 lần/ngày';

  @override
  String get schedulePreset3 => '3 lần/ngày';

  @override
  String get scheduleSlotsLabel => '2) Giờ uống thuốc (chỉnh thêm nếu cần)';

  @override
  String get scheduleAddSlot => 'Thêm giờ uống khác';

  @override
  String get schedulePillsLabel => '3) Số viên ở từng giờ uống';

  @override
  String get schedulePillsHint =>
      'Bạn có thể đặt số viên khác nhau cho từng giờ của cùng một thuốc.';

  @override
  String get scheduleSlotNoDrug => 'Chưa có thuốc nào ở giờ này.';

  @override
  String get scheduleReviewLabel => '4) Xem lại trước khi lưu';

  @override
  String get scheduleSave => 'Lưu kế hoạch';

  @override
  String get scheduleSaveSuccess => 'Đã tạo kế hoạch uống thuốc';

  @override
  String get scheduleSaveErrorConnection => 'Không kết nối được máy chủ';

  @override
  String get scheduleSaveErrorSession =>
      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';

  @override
  String get scheduleSaveErrorGeneric => 'Không thể lưu kế hoạch';

  @override
  String scheduleSaveErrorUnknown(String error) {
    return 'Lỗi: $error';
  }

  @override
  String get scheduleSlotNoSelection => 'Chưa chọn thuốc cho giờ này';

  @override
  String scheduleSlotDrugPreview(String names) {
    return 'Thuốc: $names';
  }

  @override
  String scheduleSlotDrugPreviewMore(String names, int count) {
    return 'Thuốc: $names và $count thuốc khác';
  }

  @override
  String scheduleSlotDrugCount(int count) {
    return '$count thuốc';
  }

  @override
  String get scheduleSlotChooseDrug => 'Chọn thuốc uống ở giờ này:';

  @override
  String get scheduleSlotRemoveTooltip => 'Xóa khung giờ';

  @override
  String schedulePlanTitleSingle(String name) {
    return '$name';
  }

  @override
  String schedulePlanTitleMultiple(String first, int rest) {
    return '$first và $rest thuốc khác';
  }

  @override
  String get schedulePlanTitleDefault => 'Kế hoạch thuốc';

  @override
  String scheduleSummaryDose(String time, int pills) {
    return '$time: $pills viên';
  }

  @override
  String scheduleSummaryLine(String drugName, String summary) {
    return '$drugName: $summary';
  }

  @override
  String get drugEntrySheetAddTitle => 'Thêm thuốc';

  @override
  String get drugEntrySheetEditTitle => 'Sửa thuốc';

  @override
  String get drugEntrySheetNameLabel => 'Tên thuốc *';

  @override
  String get drugEntrySheetNameHint => 'Nhập ít nhất 2 ký tự để tìm gợi ý...';

  @override
  String get drugEntrySheetDosageLabel => 'Liều lượng (tuỳ chọn)';

  @override
  String get drugEntrySheetDosageHint => 'VD: 500mg';

  @override
  String get drugEntrySheetCancel => 'Huỷ';

  @override
  String get drugEntrySheetAdd => 'Thêm';

  @override
  String get drugEntrySheetSave => 'Lưu';

  @override
  String get drugEntrySheetSearching => 'Đang tìm gợi ý...';

  @override
  String get drugEntrySheetPillsPerDoseLabel => 'Số viên/lần';

  @override
  String get drugEntrySheetTotalDaysLabel => 'Số ngày uống';
}

// lib/utils/app_strings.dart
// Central bilingual string definitions for the Chalbro app.
// All human-visible UI strings live here — never hard-code them in widgets.

class AppStrings {
  // ── Navigation ─────────────────────────────────────────────────────────────
  final String navHome;
  final String navPostTask;
  final String navFindHelp;
  final String navNearby;
  final String navTasks;
  final String navProfile;

  // ── Common ─────────────────────────────────────────────────────────────────
  final String cancel;
  final String save;
  final String logout;
  final String settings;
  final String loading;
  final String error;
  final String request;
  final String profile;
  final String yes;
  final String no;
  final String ok;
  final String continueStr; // 'continue' is a Dart keyword
  final String noInternetMessage;

  // ── Language Picker ────────────────────────────────────────────────────────
  final String langPickerTitle;
  final String langPickerSubtitle;
  final String langEnglishLabel;
  final String langHindiLabel;
  final String langEnglishNative;
  final String langHindiNative;
  final String langContinue;
  final String langChangedMsg;

  // ── Home Screen ────────────────────────────────────────────────────────────
  final String homeGreeting;
  final String homeHeroBannerTitle;
  final String homeHeroBannerSubtitle;
  final String homePostTask;
  final String homeFeaturedHelpers;
  final String homeBrowseCategories;
  final String homeOpenTasks;
  final String homeSeeAll;
  final String homeNoHelpers;
  final String homeNoOtherHelpers;
  final String homeNoTasks;
  final String homeTasksDone;
  final String homeWalletBalance;
  final String homeMedicinePickup;
  final String homeDocumentDelivery;
  final String homeGroceryShopping;
  final String homeFurnitureMoving;

  // ── Profile Screen ─────────────────────────────────────────────────────────
  final String profileTitle;
  final String profileTrustScore;
  final String profileTasksDone;
  final String profileOpenForWork;
  final String profileLetOthersFind;
  final String profileGovtId;
  final String profileMyWallet;
  final String profileNeedHelp;
  final String profileUploadingPhoto;

  // ── Settings Screen ────────────────────────────────────────────────────────
  final String settingsTitle;
  final String settingsSectionProfile;
  final String settingsSectionPreferences;
  final String settingsSectionAccount;
  final String settingsSectionLanguage;
  final String settingsProfilePhoto;
  final String settingsProfilePhotoSubtitle;
  final String settingsGovtId;
  final String settingsFullName;
  final String settingsPhone;
  final String settingsSkills;
  final String settingsSkillsHint;
  final String settingsCity;
  final String settingsSaveProfile;
  final String settingsOpenForWork;
  final String settingsOpenForWorkSubtitle;
  final String settingsHideFromSearch;
  final String settingsHideFromSearchSubtitle;
  final String settingsJoinLeaderboard;
  final String settingsJoinLeaderboardSubtitle;
  final String settingsLogout;
  final String settingsLogoutSubtitle;
  final String settingsDeleteAccount;
  final String settingsDeleteAccountSubtitle;
  final String settingsDeleteConfirmTitle;
  final String settingsDeleteConfirmBody;
  final String settingsLanguageLabel;
  final String settingsLanguageSubtitle;
  final String settingsPrivacyNoteTitle;
  final String settingsPrivacyNoteBody;
  final String settingsProfileUpdated;
  final String settingsInvalidPhone;
  final String settingsUploadingPhoto;
  final String settingsPhotoUpdated;
  final String settingsUploadingId;
  final String settingsIdSubmitted;

  // ── Post Task Screen ───────────────────────────────────────────────────────
  final String postTaskTitle;
  final String postTaskTitleLabel;
  final String postTaskDescription;
  final String postTaskBudget;
  final String postTaskCategory;
  final String postTaskDuration;
  final String postTaskStartLocation;
  final String postTaskDestLocation;
  final String postTaskCustomDuration;
  final String postTaskMarkUrgent;
  final String postTaskUrgentSubtitle;
  final String postTaskAddPhoto;
  final String postTaskRemovePhoto;
  final String postTaskPublish;
  final String postTaskPublished;
  final String postTaskEnterTitle;
  final String postTaskEnterBudget;
  final String postTaskEnterHours;
  final String postTaskRequiredForTransport;
  final String postTaskIdRequired;
  final String postTaskIdRequiredBody;
  final String postTaskRejectionReason;
  final String postTaskHowToFix;
  final String postTaskStep1;
  final String postTaskStep2;
  final String postTaskStep3;
  final String postTaskStep4;
  final String postTaskReuploadId;

  // ── Find Helpers Screen ────────────────────────────────────────────────────
  final String findHelpersTitle;
  final String findHelpersAvailableIn;
  final String findHelpersNoHelpers;
  final String findHelpersTasks;
  final String findHelpersFilterAll;
  final String findHelpersFilterHighRated;

  // ── Wallet Screen ──────────────────────────────────────────────────────────
  final String walletTitle;
  final String walletAvailableBalance;
  final String walletAddMoney;
  final String walletTopUp;
  final String walletTransactionHistory;
  final String walletNoTransactions;
  final String walletAddedSuccess;
  final String walletAddedFailed;

  // ── Notifications Screen ───────────────────────────────────────────────────
  final String notificationsTitle;
  final String notificationsEmpty;
  final String notificationsError;

  // ── Chat List Screen ───────────────────────────────────────────────────────
  final String chatTitle;
  final String chatEmpty;
  final String chatLoading;

  // ── Terms Screen ───────────────────────────────────────────────────────────
  final String termsTitle;
  final String termsSubtitle;
  final String termsScrollHint;
  final String termsAcceptButton;
  final String termsReadAll;
  final String termsFooter;
  final String termsS0Title;
  final String termsS0Body;
  final String termsS1Title;
  final String termsS1Body;
  final String termsS2Title;
  final String termsS2Body;
  final String termsS3Title;
  final String termsS3Body;
  final String termsS4Title;
  final String termsS4Body;
  final String termsS5Title;
  final String termsS5Body;
  final String termsS6Title;
  final String termsS6Body;
  final String termsS7Title;
  final String termsS7Body;
  final String termsS8Title;
  final String termsS8Body;
  final String termsS9Title;
  final String termsS9Body;
  final String termsS10Title;
  final String termsS10Body;
  final String termsS11Title;
  final String termsS11Body;

  const AppStrings({
    required this.navHome,
    required this.navPostTask,
    required this.navFindHelp,
    required this.navNearby,
    required this.navTasks,
    required this.navProfile,
    required this.cancel,
    required this.save,
    required this.logout,
    required this.settings,
    required this.loading,
    required this.error,
    required this.request,
    required this.profile,
    required this.yes,
    required this.no,
    required this.ok,
    required this.continueStr,
    required this.noInternetMessage,
    required this.langPickerTitle,
    required this.langPickerSubtitle,
    required this.langEnglishLabel,
    required this.langHindiLabel,
    required this.langEnglishNative,
    required this.langHindiNative,
    required this.langContinue,
    required this.langChangedMsg,
    required this.homeGreeting,
    required this.homeHeroBannerTitle,
    required this.homeHeroBannerSubtitle,
    required this.homePostTask,
    required this.homeFeaturedHelpers,
    required this.homeBrowseCategories,
    required this.homeOpenTasks,
    required this.homeSeeAll,
    required this.homeNoHelpers,
    required this.homeNoOtherHelpers,
    required this.homeNoTasks,
    required this.homeTasksDone,
    required this.homeWalletBalance,
    required this.homeMedicinePickup,
    required this.homeDocumentDelivery,
    required this.homeGroceryShopping,
    required this.homeFurnitureMoving,
    required this.profileTitle,
    required this.profileTrustScore,
    required this.profileTasksDone,
    required this.profileOpenForWork,
    required this.profileLetOthersFind,
    required this.profileGovtId,
    required this.profileMyWallet,
    required this.profileNeedHelp,
    required this.profileUploadingPhoto,
    required this.settingsTitle,
    required this.settingsSectionProfile,
    required this.settingsSectionPreferences,
    required this.settingsSectionAccount,
    required this.settingsSectionLanguage,
    required this.settingsProfilePhoto,
    required this.settingsProfilePhotoSubtitle,
    required this.settingsGovtId,
    required this.settingsFullName,
    required this.settingsPhone,
    required this.settingsSkills,
    required this.settingsSkillsHint,
    required this.settingsCity,
    required this.settingsSaveProfile,
    required this.settingsOpenForWork,
    required this.settingsOpenForWorkSubtitle,
    required this.settingsHideFromSearch,
    required this.settingsHideFromSearchSubtitle,
    required this.settingsJoinLeaderboard,
    required this.settingsJoinLeaderboardSubtitle,
    required this.settingsLogout,
    required this.settingsLogoutSubtitle,
    required this.settingsDeleteAccount,
    required this.settingsDeleteAccountSubtitle,
    required this.settingsDeleteConfirmTitle,
    required this.settingsDeleteConfirmBody,
    required this.settingsLanguageLabel,
    required this.settingsLanguageSubtitle,
    required this.settingsPrivacyNoteTitle,
    required this.settingsPrivacyNoteBody,
    required this.settingsProfileUpdated,
    required this.settingsInvalidPhone,
    required this.settingsUploadingPhoto,
    required this.settingsPhotoUpdated,
    required this.settingsUploadingId,
    required this.settingsIdSubmitted,
    required this.postTaskTitle,
    required this.postTaskTitleLabel,
    required this.postTaskDescription,
    required this.postTaskBudget,
    required this.postTaskCategory,
    required this.postTaskDuration,
    required this.postTaskStartLocation,
    required this.postTaskDestLocation,
    required this.postTaskCustomDuration,
    required this.postTaskMarkUrgent,
    required this.postTaskUrgentSubtitle,
    required this.postTaskAddPhoto,
    required this.postTaskRemovePhoto,
    required this.postTaskPublish,
    required this.postTaskPublished,
    required this.postTaskEnterTitle,
    required this.postTaskEnterBudget,
    required this.postTaskEnterHours,
    required this.postTaskRequiredForTransport,
    required this.postTaskIdRequired,
    required this.postTaskIdRequiredBody,
    required this.postTaskRejectionReason,
    required this.postTaskHowToFix,
    required this.postTaskStep1,
    required this.postTaskStep2,
    required this.postTaskStep3,
    required this.postTaskStep4,
    required this.postTaskReuploadId,
    required this.findHelpersTitle,
    required this.findHelpersAvailableIn,
    required this.findHelpersNoHelpers,
    required this.findHelpersTasks,
    required this.findHelpersFilterAll,
    required this.findHelpersFilterHighRated,
    required this.walletTitle,
    required this.walletAvailableBalance,
    required this.walletAddMoney,
    required this.walletTopUp,
    required this.walletTransactionHistory,
    required this.walletNoTransactions,
    required this.walletAddedSuccess,
    required this.walletAddedFailed,
    required this.notificationsTitle,
    required this.notificationsEmpty,
    required this.notificationsError,
    required this.chatTitle,
    required this.chatEmpty,
    required this.chatLoading,
    required this.termsTitle,
    required this.termsSubtitle,
    required this.termsScrollHint,
    required this.termsAcceptButton,
    required this.termsReadAll,
    required this.termsFooter,
    required this.termsS0Title,
    required this.termsS0Body,
    required this.termsS1Title,
    required this.termsS1Body,
    required this.termsS2Title,
    required this.termsS2Body,
    required this.termsS3Title,
    required this.termsS3Body,
    required this.termsS4Title,
    required this.termsS4Body,
    required this.termsS5Title,
    required this.termsS5Body,
    required this.termsS6Title,
    required this.termsS6Body,
    required this.termsS7Title,
    required this.termsS7Body,
    required this.termsS8Title,
    required this.termsS8Body,
    required this.termsS9Title,
    required this.termsS9Body,
    required this.termsS10Title,
    required this.termsS10Body,
    required this.termsS11Title,
    required this.termsS11Body,
  });

  // ── English ─────────────────────────────────────────────────────────────────
  static const AppStrings en = AppStrings(
    navHome: 'Home',
    navPostTask: 'Post Task',
    navFindHelp: 'Find Help',
    navNearby: 'Nearby',
    navTasks: 'Tasks',
    navProfile: 'Profile',
    cancel: 'Cancel',
    save: 'Save',
    logout: 'Logout',
    settings: 'Settings',
    loading: 'Loading...',
    error: 'Something went wrong.',
    request: 'Request',
    profile: 'Profile',
    yes: 'Yes',
    no: 'No',
    ok: 'OK',
    continueStr: 'Continue',
    noInternetMessage: 'No internet connection. Please check your network.',
    langPickerTitle: 'Choose Language',
    langPickerSubtitle: 'भाषा चुनें',
    langEnglishLabel: 'English',
    langHindiLabel: 'हिंदी',
    langEnglishNative: 'English',
    langHindiNative: 'Hindi',
    langContinue: 'Continue',
    langChangedMsg: 'Language changed to English',
    homeGreeting: 'Namaste 👋',
    homeHeroBannerTitle: 'Need help with something?',
    homeHeroBannerSubtitle: 'Post a task. Helpers nearby will apply.',
    homePostTask: 'Post a Task',
    homeFeaturedHelpers: 'Featured Helpers',
    homeBrowseCategories: 'Browse categories',
    homeOpenTasks: 'Open tasks near you',
    homeSeeAll: 'See all',
    homeNoHelpers: 'No helpers nearby currently.',
    homeNoOtherHelpers: 'No other helpers nearby currently.',
    homeNoTasks: 'No open tasks near you.',
    homeTasksDone: 'Tasks Done',
    homeWalletBalance: 'Wallet Balance',
    homeMedicinePickup: 'Medicine Pickup',
    homeDocumentDelivery: 'Document Delivery',
    homeGroceryShopping: 'Grocery Shopping',
    homeFurnitureMoving: 'Furniture Moving',
    profileTitle: 'Profile',
    profileTrustScore: 'Trust Score',
    profileTasksDone: 'Tasks Done',
    profileOpenForWork: 'Open for Work',
    profileLetOthersFind: 'Let others find you',
    profileGovtId: 'Govt ID',
    profileMyWallet: 'My Wallet',
    profileNeedHelp: 'Need Help? Contact Support',
    profileUploadingPhoto: 'Uploading photo...',
    settingsTitle: 'Settings',
    settingsSectionProfile: 'Profile',
    settingsSectionPreferences: 'Preferences',
    settingsSectionAccount: 'Account',
    settingsSectionLanguage: 'Language',
    settingsProfilePhoto: 'Profile Photo',
    settingsProfilePhotoSubtitle: 'Tap to upload a new photo',
    settingsGovtId: 'Government ID Proof',
    settingsFullName: 'Full Name',
    settingsPhone: 'Phone Number',
    settingsSkills: 'Skills / Qualifications',
    settingsSkillsHint: 'e.g. Plumber, Driver, Tutor',
    settingsCity: 'City',
    settingsSaveProfile: 'Save Profile Changes',
    settingsOpenForWork: 'Open for Work',
    settingsOpenForWorkSubtitle: 'Allow others to find and hire you',
    settingsHideFromSearch: 'Hide from Search',
    settingsHideFromSearchSubtitle: "Your profile won't appear in Find Helpers",
    settingsJoinLeaderboard: 'Join Leaderboard',
    settingsJoinLeaderboardSubtitle: 'Show your full name on the public rankings',
    settingsLogout: 'Logout',
    settingsLogoutSubtitle: 'Sign out of your account',
    settingsDeleteAccount: 'Delete Account',
    settingsDeleteAccountSubtitle: 'Permanently remove all your data',
    settingsDeleteConfirmTitle: 'Delete Account?',
    settingsDeleteConfirmBody:
        'This will permanently delete your account and all associated data. This action cannot be undone.',
    settingsLanguageLabel: 'App Language',
    settingsLanguageSubtitle: 'English / हिंदी',
    settingsPrivacyNoteTitle: 'Privacy Note',
    settingsPrivacyNoteBody:
        '• Leaderboard: Only users who have completed at least 1 task can appear. '
        'Your full name is shown only if you opt in. Otherwise, only a masked name '
        '(e.g. "Ja****") is displayed and your profile cannot be tapped.\n\n'
        '• Hide from Search: When enabled, your profile will not appear in the '
        'Find Helpers list even if Open for Work is turned on.',
    settingsProfileUpdated: 'Profile updated successfully!',
    settingsInvalidPhone: 'Please enter a valid 10-digit phone number.',
    settingsUploadingPhoto: 'Uploading photo...',
    settingsPhotoUpdated: 'Profile photo updated!',
    settingsUploadingId: 'Uploading ID Proof...',
    settingsIdSubmitted: 'ID Proof submitted for verification.',
    postTaskTitle: 'Post a Task',
    postTaskTitleLabel: 'Task Title',
    postTaskDescription: 'Description (Optional)',
    postTaskBudget: 'Budget (₹)',
    postTaskCategory: 'Category',
    postTaskDuration: 'Task Duration (Ends automatically)',
    postTaskStartLocation: 'Start Location',
    postTaskDestLocation: 'Destination Location',
    postTaskCustomDuration: 'Custom Duration (Hours)',
    postTaskMarkUrgent: 'Mark as Urgent',
    postTaskUrgentSubtitle: 'Needs immediate attention',
    postTaskAddPhoto: 'Add Photo (Optional)',
    postTaskRemovePhoto: 'Remove Photo',
    postTaskPublish: 'Post Task live',
    postTaskPublished: 'Task published',
    postTaskEnterTitle: 'Enter a title',
    postTaskEnterBudget: 'Enter your budget',
    postTaskEnterHours: 'Enter hours',
    postTaskRequiredForTransport: 'Required for Transport',
    postTaskIdRequired: 'Proper Photo ID Required',
    postTaskIdRequiredBody:
        'Your ID photo was rejected by our team.\nYou must submit a valid ID to post tasks.',
    postTaskRejectionReason: 'REJECTION REASON:',
    postTaskHowToFix: 'How to fix this:',
    postTaskStep1: 'Take a clear, well-lit photo of your ID',
    postTaskStep2: 'Make sure all text & corners are visible',
    postTaskStep3: 'Upload via your Profile → ID Proof',
    postTaskStep4: 'Admin reviews within 24 hours',
    postTaskReuploadId: 'Re-upload Photo ID',
    findHelpersTitle: 'Find Helpers',
    findHelpersAvailableIn: 'Available in',
    findHelpersNoHelpers: 'No active helpers currently available in your city.',
    findHelpersTasks: 'tasks',
    findHelpersFilterAll: 'All',
    findHelpersFilterHighRated: 'High Rated',
    walletTitle: 'My Wallet',
    walletAvailableBalance: 'Available Balance',
    walletAddMoney: 'Add Money',
    walletTopUp: 'Top Up Wallet',
    walletTransactionHistory: 'Transaction History',
    walletNoTransactions: 'No transactions yet',
    walletAddedSuccess: 'Added to wallet!',
    walletAddedFailed: 'Failed to add money.',
    notificationsTitle: 'Notifications',
    notificationsEmpty: 'No new notifications.',
    notificationsError: 'Error loading notifications.',
    chatTitle: 'Messages',
    chatEmpty: 'No messages yet',
    chatLoading: 'Loading...',
    termsTitle: 'Terms & Conditions',
    termsSubtitle: 'Please read and accept before continuing',
    termsScrollHint: 'Scroll to read all terms',
    termsAcceptButton: 'I Accept — Continue to App',
    termsReadAll: 'Read All Terms to Continue',
    termsFooter:
        'By tapping "I Accept", you confirm that you have read, understood, and agree to be bound by all of the above Terms & Conditions and Disclaimers.',
    termsS0Title: '⚠️ Important Disclaimer',
    termsS0Body:
        'Chalbro is a technology platform that connects individuals seeking help with tasks ("Task Posters") and individuals willing to perform such tasks ("Helpers"). Chalbro does NOT employ any Helper and is NOT responsible for the quality, safety, or legality of any task performed through this platform.',
    termsS1Title: '1. Nature of the Platform',
    termsS1Body:
        'Chalbro acts solely as an intermediary marketplace. All agreements for task performance are strictly between Task Posters and Helpers. Chalbro is not a party to any such agreement and makes no guarantees regarding the completion, quality, or outcome of any task.',
    termsS2Title: '2. User Eligibility',
    termsS2Body:
        'You must be at least 18 years of age to use this platform. By accepting these terms, you confirm that you are legally capable of entering into binding contracts. If you are under 18, you must not use this app.',
    termsS3Title: '3. Safety & Risk Disclaimer',
    termsS3Body:
        'Chalbro does not conduct background checks on all users. Meeting strangers always carries inherent risks. You are solely responsible for your own safety. Chalbro strongly recommends:\n\n• Always meeting in public places for the first time\n• Sharing task details with a trusted friend or family member\n• Reporting suspicious behavior immediately through the app\n• Never sharing your financial passwords or sensitive personal data\n\nChalbro shall not be liable for any personal injury, death, property damage, or any other harm resulting from interactions between users.',
    termsS4Title: '4. Financial Transactions & Wallet',
    termsS4Body:
        'The in-app wallet balance is virtual currency for transactional purposes within the app. All wallet top-ups and withdrawals are subject to applicable taxes and platform fees. A 10% platform fee is deducted from every completed task payment. Chalbro is not liable for any financial loss arising from disputes between users, fraudulent transactions, or platform outages. Wallet balances are non-transferable and non-refundable except as required by applicable law.',
    termsS5Title: '5. Prohibited Activities',
    termsS5Body:
        'You agree NOT to use Chalbro for:\n\n• Any illegal activities\n• Solicitation of sexual services\n• Harassment, abuse, or threats of any kind\n• Posting false or misleading task information\n• Attempting to conduct transactions outside the platform\n• Fraudulent reviews or ratings manipulation\n\nViolation of these rules will result in immediate account suspension and may be reported to law enforcement authorities.',
    termsS6Title: '6. Identity Verification',
    termsS6Body:
        'You may be required to upload a Government-issued ID for verification purposes. By uploading your ID, you consent to Chalbro storing and processing this data for verification purposes only. Your ID document will not be shared with other users.',
    termsS7Title: '7. Privacy Policy',
    termsS7Body:
        'Your personal data (name, phone, city, profile photo) is collected and used solely to provide the Chalbro service. We do not sell your personal data to third parties. Location data (city) is used to match you with nearby tasks and helpers. By accepting these terms, you also consent to our Privacy Policy available at chalbroo.app/privacy.',
    termsS8Title: '8. Content & Conduct',
    termsS8Body:
        'You are responsible for all content you post on Chalbro, including task descriptions, messages, and reviews. Chalbro reserves the right to remove any content that violates these terms or is deemed inappropriate at our sole discretion.',
    termsS9Title: '9. Limitation of Liability',
    termsS9Body:
        'TO THE MAXIMUM EXTENT PERMITTED BY LAW, CHALBRO SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING LOSS OF PROFITS, DATA, USE, GOODWILL, OR OTHER INTANGIBLE LOSSES, RESULTING FROM YOUR USE OF OR INABILITY TO USE THE SERVICE.',
    termsS10Title: '10. Changes to Terms',
    termsS10Body:
        'Chalbro reserves the right to update these Terms & Conditions at any time. Continued use of the platform after changes constitutes acceptance of the new terms. We will notify you of significant changes via the app.',
    termsS11Title: '11. Governing Law',
    termsS11Body:
        'These Terms are governed by the laws of India. Any disputes arising from the use of this platform shall be subject to the exclusive jurisdiction of the courts of Surat, Gujarat, India.\n\nLast updated: July 2026',
  );

  // ── Hindi ───────────────────────────────────────────────────────────────────
  static const AppStrings hi = AppStrings(
    navHome: 'होम',
    navPostTask: 'काम पोस्ट',
    navFindHelp: 'सहायक',
    navNearby: 'नज़दीक',
    navTasks: 'काम',
    navProfile: 'प्रोफ़ाइल',
    cancel: 'रद्द करें',
    save: 'सेव करें',
    logout: 'लॉगआउट',
    settings: 'सेटिंग्स',
    loading: 'लोड हो रहा है...',
    error: 'कुछ गलत हो गया।',
    request: 'अनुरोध करें',
    profile: 'प्रोफ़ाइल',
    yes: 'हाँ',
    no: 'नहीं',
    ok: 'ठीक है',
    continueStr: 'जारी रखें',
    noInternetMessage: 'इंटरनेट नहीं है। कृपया अपना नेटवर्क जाँचें।',
    langPickerTitle: 'भाषा चुनें',
    langPickerSubtitle: 'Choose Language',
    langEnglishLabel: 'अंग्रेज़ी',
    langHindiLabel: 'हिंदी',
    langEnglishNative: 'English',
    langHindiNative: 'हिंदी',
    langContinue: 'जारी रखें',
    langChangedMsg: 'भाषा हिंदी में बदली गई',
    homeGreeting: 'नमस्ते 👋',
    homeHeroBannerTitle: 'किसी काम में मदद चाहिए?',
    homeHeroBannerSubtitle: 'काम पोस्ट करें। नज़दीकी सहायक आवेदन करेंगे।',
    homePostTask: 'काम पोस्ट करें',
    homeFeaturedHelpers: 'चुनिंदा सहायक',
    homeBrowseCategories: 'श्रेणियाँ देखें',
    homeOpenTasks: 'आपके नज़दीक खुले काम',
    homeSeeAll: 'सभी देखें',
    homeNoHelpers: 'अभी आपके नज़दीक कोई सहायक नहीं है।',
    homeNoOtherHelpers: 'अभी आपके नज़दीक कोई अन्य सहायक नहीं है।',
    homeNoTasks: 'आपके नज़दीक कोई खुला काम नहीं है।',
    homeTasksDone: 'काम पूरे किए',
    homeWalletBalance: 'वॉलेट बैलेंस',
    homeMedicinePickup: 'दवाई लाना',
    homeDocumentDelivery: 'दस्तावेज़ डिलीवरी',
    homeGroceryShopping: 'किराना खरीदारी',
    homeFurnitureMoving: 'फर्नीचर शिफ्टिंग',
    profileTitle: 'प्रोफ़ाइल',
    profileTrustScore: 'विश्वास स्कोर',
    profileTasksDone: 'काम पूरे किए',
    profileOpenForWork: 'काम के लिए उपलब्ध',
    profileLetOthersFind: 'दूसरों को ढूँढने दें',
    profileGovtId: 'सरकारी ID',
    profileMyWallet: 'मेरा वॉलेट',
    profileNeedHelp: 'मदद चाहिए? सपोर्ट से संपर्क करें',
    profileUploadingPhoto: 'फ़ोटो अपलोड हो रही है...',
    settingsTitle: 'सेटिंग्स',
    settingsSectionProfile: 'प्रोफ़ाइल',
    settingsSectionPreferences: 'प्राथमिकताएँ',
    settingsSectionAccount: 'अकाउंट',
    settingsSectionLanguage: 'भाषा',
    settingsProfilePhoto: 'प्रोफ़ाइल फ़ोटो',
    settingsProfilePhotoSubtitle: 'नई फ़ोटो अपलोड करने के लिए टैप करें',
    settingsGovtId: 'सरकारी ID प्रमाण',
    settingsFullName: 'पूरा नाम',
    settingsPhone: 'फ़ोन नंबर',
    settingsSkills: 'कौशल / योग्यता',
    settingsSkillsHint: 'उदा. प्लंबर, ड्राइवर, ट्यूटर',
    settingsCity: 'शहर',
    settingsSaveProfile: 'प्रोफ़ाइल परिवर्तन सेव करें',
    settingsOpenForWork: 'काम के लिए उपलब्ध',
    settingsOpenForWorkSubtitle: 'दूसरों को आपको ढूँढने और काम देने दें',
    settingsHideFromSearch: 'खोज से छुपाएँ',
    settingsHideFromSearchSubtitle: 'आपकी प्रोफ़ाइल सहायक खोज में नहीं दिखेगी',
    settingsJoinLeaderboard: 'लीडरबोर्ड में शामिल हों',
    settingsJoinLeaderboardSubtitle: 'सार्वजनिक रैंकिंग पर अपना पूरा नाम दिखाएँ',
    settingsLogout: 'लॉगआउट',
    settingsLogoutSubtitle: 'अपने अकाउंट से साइन आउट करें',
    settingsDeleteAccount: 'अकाउंट हटाएँ',
    settingsDeleteAccountSubtitle: 'अपना सारा डेटा स्थायी रूप से हटाएँ',
    settingsDeleteConfirmTitle: 'अकाउंट हटाएँ?',
    settingsDeleteConfirmBody:
        'यह आपके अकाउंट और सभी संबंधित डेटा को स्थायी रूप से हटा देगा। यह क्रिया पूर्ववत नहीं की जा सकती।',
    settingsLanguageLabel: 'ऐप की भाषा',
    settingsLanguageSubtitle: 'English / हिंदी',
    settingsPrivacyNoteTitle: 'गोपनीयता नोट',
    settingsPrivacyNoteBody:
        '• लीडरबोर्ड: केवल वे उपयोगकर्ता दिख सकते हैं जिन्होंने कम से कम 1 काम पूरा किया हो। '
        'आपका पूरा नाम केवल तभी दिखता है जब आप सहमति देते हैं। अन्यथा केवल छुपा हुआ नाम '
        '(जैसे "Ja****") दिखाया जाता है।\n\n'
        '• खोज से छुपाएँ: सक्षम होने पर, काम के लिए उपलब्ध होने पर भी आपकी प्रोफ़ाइल सहायक सूची में नहीं दिखेगी।',
    settingsProfileUpdated: 'प्रोफ़ाइल सफलतापूर्वक अपडेट हो गई!',
    settingsInvalidPhone: 'कृपया एक वैध 10 अंकों का फ़ोन नंबर दर्ज करें।',
    settingsUploadingPhoto: 'फ़ोटो अपलोड हो रही है...',
    settingsPhotoUpdated: 'प्रोफ़ाइल फ़ोटो अपडेट हो गई!',
    settingsUploadingId: 'ID प्रमाण अपलोड हो रहा है...',
    settingsIdSubmitted: 'ID प्रमाण सत्यापन के लिए जमा किया गया।',
    postTaskTitle: 'काम पोस्ट करें',
    postTaskTitleLabel: 'काम का शीर्षक',
    postTaskDescription: 'विवरण (वैकल्पिक)',
    postTaskBudget: 'बजट (₹)',
    postTaskCategory: 'श्रेणी',
    postTaskDuration: 'काम की अवधि (स्वचालित रूप से समाप्त)',
    postTaskStartLocation: 'शुरुआत का स्थान',
    postTaskDestLocation: 'गंतव्य स्थान',
    postTaskCustomDuration: 'कस्टम अवधि (घंटे)',
    postTaskMarkUrgent: 'अत्यावश्यक चिह्नित करें',
    postTaskUrgentSubtitle: 'तुरंत ध्यान देने की ज़रूरत है',
    postTaskAddPhoto: 'फ़ोटो जोड़ें (वैकल्पिक)',
    postTaskRemovePhoto: 'फ़ोटो हटाएँ',
    postTaskPublish: 'काम प्रकाशित करें',
    postTaskPublished: 'काम प्रकाशित हो गया',
    postTaskEnterTitle: 'शीर्षक दर्ज करें',
    postTaskEnterBudget: 'अपना बजट दर्ज करें',
    postTaskEnterHours: 'घंटे दर्ज करें',
    postTaskRequiredForTransport: 'परिवहन के लिए आवश्यक',
    postTaskIdRequired: 'वैध फ़ोटो ID आवश्यक है',
    postTaskIdRequiredBody:
        'आपकी ID फ़ोटो हमारी टीम द्वारा अस्वीकार की गई।\nकाम पोस्ट करने के लिए आपको एक वैध ID जमा करनी होगी।',
    postTaskRejectionReason: 'अस्वीकृति का कारण:',
    postTaskHowToFix: 'इसे कैसे ठीक करें:',
    postTaskStep1: 'अपनी ID की एक स्पष्ट, अच्छी रोशनी वाली फ़ोटो लें',
    postTaskStep2: 'सुनिश्चित करें कि सभी टेक्स्ट और कोने दिख रहे हैं',
    postTaskStep3: 'प्रोफ़ाइल → ID प्रमाण के माध्यम से अपलोड करें',
    postTaskStep4: 'एडमिन 24 घंटों में समीक्षा करता है',
    postTaskReuploadId: 'फ़ोटो ID पुनः अपलोड करें',
    findHelpersTitle: 'सहायक खोजें',
    findHelpersAvailableIn: 'में उपलब्ध',
    findHelpersNoHelpers: 'अभी आपके शहर में कोई सक्रिय सहायक उपलब्ध नहीं है।',
    findHelpersTasks: 'काम',
    findHelpersFilterAll: 'सभी',
    findHelpersFilterHighRated: 'उच्च रेटेड',
    walletTitle: 'मेरा वॉलेट',
    walletAvailableBalance: 'उपलब्ध बैलेंस',
    walletAddMoney: 'पैसे जोड़ें',
    walletTopUp: 'वॉलेट टॉप अप करें',
    walletTransactionHistory: 'लेनदेन इतिहास',
    walletNoTransactions: 'अभी तक कोई लेनदेन नहीं',
    walletAddedSuccess: 'वॉलेट में जोड़ा गया!',
    walletAddedFailed: 'पैसे जोड़ने में विफल।',
    notificationsTitle: 'सूचनाएँ',
    notificationsEmpty: 'कोई नई सूचना नहीं।',
    notificationsError: 'सूचनाएँ लोड करने में त्रुटि।',
    chatTitle: 'संदेश',
    chatEmpty: 'अभी तक कोई संदेश नहीं',
    chatLoading: 'लोड हो रहा है...',
    termsTitle: 'नियम एवं शर्तें',
    termsSubtitle: 'जारी रखने से पहले कृपया पढ़ें और स्वीकार करें',
    termsScrollHint: 'सभी नियम पढ़ने के लिए स्क्रॉल करें',
    termsAcceptButton: 'मैं स्वीकार करता/करती हूँ — ऐप में जारी रखें',
    termsReadAll: 'जारी रखने के लिए सभी नियम पढ़ें',
    termsFooter:
        '"मैं स्वीकार करता/करती हूँ" टैप करके आप पुष्टि करते हैं कि आपने उपरोक्त सभी नियमों, शर्तों और अस्वीकरणों को पढ़ा, समझा और उनसे सहमत हैं।',
    termsS0Title: '⚠️ महत्वपूर्ण अस्वीकरण',
    termsS0Body:
        'Chalbro एक तकनीकी मंच है जो काम की तलाश करने वाले व्यक्तियों ("टास्क पोस्टर") और काम करने को तैयार व्यक्तियों ("सहायक") को जोड़ता है। Chalbro किसी भी सहायक को नियुक्त नहीं करता और इस मंच के माध्यम से किए गए किसी भी काम की गुणवत्ता, सुरक्षा या वैधता के लिए जिम्मेदार नहीं है।',
    termsS1Title: '1. मंच की प्रकृति',
    termsS1Body:
        'Chalbro केवल एक मध्यस्थ बाज़ार के रूप में कार्य करता है। काम के प्रदर्शन के लिए सभी समझौते केवल टास्क पोस्टर और सहायक के बीच होते हैं। Chalbro किसी भी ऐसे समझौते का पक्षकार नहीं है और किसी भी काम के पूरा होने, गुणवत्ता या परिणाम की कोई गारंटी नहीं देता।',
    termsS2Title: '2. उपयोगकर्ता पात्रता',
    termsS2Body:
        'इस मंच का उपयोग करने के लिए आपकी आयु कम से कम 18 वर्ष होनी चाहिए। इन शर्तों को स्वीकार करके, आप पुष्टि करते हैं कि आप बाध्यकारी अनुबंधों में प्रवेश करने में कानूनी रूप से सक्षम हैं।',
    termsS3Title: '3. सुरक्षा एवं जोखिम अस्वीकरण',
    termsS3Body:
        'Chalbro सभी उपयोगकर्ताओं की पृष्ठभूमि जाँच नहीं करता। अजनबियों से मिलने में हमेशा स्वाभाविक जोखिम होते हैं। आप अपनी सुरक्षा के लिए स्वयं ज़िम्मेदार हैं। Chalbro दृढ़ता से अनुशंसा करता है:\n\n• पहली बार हमेशा सार्वजनिक स्थानों पर मिलें\n• किसी विश्वसनीय मित्र या परिवार के साथ काम का विवरण साझा करें\n• ऐप के माध्यम से तुरंत संदिग्ध व्यवहार की रिपोर्ट करें\n• वित्तीय पासवर्ड या संवेदनशील डेटा कभी साझा न करें',
    termsS4Title: '4. वित्तीय लेनदेन एवं वॉलेट',
    termsS4Body:
        'इन-ऐप वॉलेट बैलेंस आभासी मुद्रा है। सभी टॉप-अप और निकासी पर कर व प्लेटफ़ॉर्म शुल्क लागू होते हैं। प्रत्येक पूर्ण भुगतान से 10% प्लेटफ़ॉर्म शुल्क काटा जाता है।',
    termsS5Title: '5. निषिद्ध गतिविधियाँ',
    termsS5Body:
        'आप सहमत हैं कि Chalbro का उपयोग नहीं करेंगे:\n\n• किसी भी अवैध गतिविधि के लिए\n• यौन सेवाओं की मांग के लिए\n• उत्पीड़न, दुर्व्यवहार या धमकी के लिए\n• झूठी काम की जानकारी पोस्ट करने के लिए\n• प्लेटफ़ॉर्म के बाहर लेनदेन करने के लिए\n• धोखाधड़ी समीक्षाओं के लिए',
    termsS6Title: '6. पहचान सत्यापन',
    termsS6Body:
        'सत्यापन के लिए आपको सरकारी ID अपलोड करनी हो सकती है। अपलोड करके आप केवल सत्यापन हेतु डेटा संग्रह की सहमति देते हैं। आपकी ID अन्य उपयोगकर्ताओं के साथ साझा नहीं की जाएगी।',
    termsS7Title: '7. गोपनीयता नीति',
    termsS7Body:
        'आपका व्यक्तिगत डेटा केवल Chalbro सेवा प्रदान करने के लिए उपयोग किया जाता है। हम आपका डेटा तृतीय पक्षों को नहीं बेचते। इन शर्तों को स्वीकार करके, आप chalbroo.app/privacy पर उपलब्ध गोपनीयता नीति से भी सहमत हैं।',
    termsS8Title: '8. सामग्री एवं आचरण',
    termsS8Body:
        'आप Chalbro पर पोस्ट की गई सभी सामग्री के लिए ज़िम्मेदार हैं। Chalbro नियमों का उल्लंघन करने वाली किसी भी सामग्री को हटाने का अधिकार सुरक्षित रखता है।',
    termsS9Title: '9. देयता की सीमा',
    termsS9Body:
        'कानून द्वारा अनुमत अधिकतम सीमा तक, CHALBRO किसी भी अप्रत्यक्ष, आकस्मिक या परिणामी क्षतियों के लिए उत्तरदायी नहीं होगा।',
    termsS10Title: '10. शर्तों में परिवर्तन',
    termsS10Body:
        'Chalbro किसी भी समय इन शर्तों को अपडेट करने का अधिकार सुरक्षित रखता है। परिवर्तनों के बाद मंच का उपयोग जारी रखना नई शर्तों की स्वीकृति माना जाएगा।',
    termsS11Title: '11. शासी कानून',
    termsS11Body:
        'ये शर्तें भारत के कानूनों द्वारा शासित हैं। इस मंच से उत्पन्न किसी भी विवाद को सूरत, गुजरात, भारत की अदालतों के क्षेत्राधिकार के अधीन किया जाएगा।\n\nअंतिम अपडेट: जुलाई 2026',
  );
}

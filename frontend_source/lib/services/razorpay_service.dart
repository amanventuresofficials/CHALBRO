import 'package:cloud_functions/cloud_functions.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Drives the real Razorpay checkout flow. Order creation and payment
/// verification both happen in Cloud Functions (createRazorpayOrder /
/// verifyRazorpayPayment) so the amount and the signature are never trusted
/// from the client.
class RazorpayService {
  final Razorpay _razorpay = Razorpay();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String? _taskId;
  String? _workerUid;
  double? _givenRating;
  void Function()? _onSuccess;
  void Function(String message)? _onError;

  RazorpayService() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  Future<void> payForTask({
    required String taskId,
    required String workerUid,
    required double givenRating,
    required String posterName,
    required String posterContact,
    required void Function() onSuccess,
    required void Function(String message) onError,
  }) async {
    _taskId = taskId;
    _workerUid = workerUid;
    _givenRating = givenRating;
    _onSuccess = onSuccess;
    _onError = onError;

    try {
      final createOrder = _functions.httpsCallable('createRazorpayOrder');
      final result = await createOrder.call({'taskId': taskId});
      final data = result.data as Map;

      final options = {
        'key': data['keyId'],
        'amount': data['amount'],
        'currency': data['currency'],
        'order_id': data['orderId'],
        'name': 'ChalBro',
        'description': 'Task payment',
        'prefill': {'name': posterName, 'contact': posterContact},
      };
      _razorpay.open(options);
    } catch (e) {
      onError('Could not start payment: $e');
    }
  }

  void _handleSuccess(PaymentSuccessResponse response) async {
    try {
      final verify = _functions.httpsCallable('verifyRazorpayPayment');
      await verify.call({
        'taskId': _taskId,
        'workerUid': _workerUid,
        'givenRating': _givenRating,
        'razorpayOrderId': response.orderId,
        'razorpayPaymentId': response.paymentId,
        'razorpaySignature': response.signature,
      });
      _onSuccess?.call();
    } catch (e) {
      _onError?.call('Payment succeeded but could not be confirmed: $e');
    }
  }

  void _handleError(PaymentFailureResponse response) {
    _onError?.call(response.message ?? 'Payment failed or was cancelled.');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // No-op: user picked an external wallet app; Razorpay handles that flow itself.
  }

  void dispose() {
    _razorpay.clear();
  }
}

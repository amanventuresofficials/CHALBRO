import 'package:cloud_functions/cloud_functions.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'error_logger.dart';

/// Drives the real Razorpay checkout flow. Order creation and payment
/// verification both happen in Cloud Functions (createRazorpayOrder /
/// verifyRazorpayPayment) so the amount and the signature are never trusted
/// from the client.
class RazorpayService {
  final Razorpay _razorpay = Razorpay();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String? _taskId;
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
    required double givenRating,
    required String posterName,
    required String posterContact,
    required void Function() onSuccess,
    required void Function(String message) onError,
  }) async {
    _taskId = taskId;
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
    } catch (e, st) {
      ErrorLogger.instance.log(
        error: e,
        stack: st,
        category: 'payment',
        context: 'Razorpay: start payment (create order)',
        taskId: taskId,
      );
      onError(_startErrorMessage(e));
    }
  }

  /// Plain words for the person paying. The technical detail stays in the error log.
  static String _startErrorMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'failed-precondition':
        case 'permission-denied':
        case 'invalid-argument':
          // These are written for the user by the server ("This task has already been paid." ...).
          if ((e.message ?? '').isNotEmpty) return e.message!;
          break;
        case 'unauthenticated':
          return 'Please log in again and retry the payment.';
      }
      // not-found / unavailable / internal: the payment server cannot be reached.
      return 'Online payment is not available right now. Please try again in a little while.';
    }
    return 'Could not start the payment. Please check your connection and try again.';
  }

  void _handleSuccess(PaymentSuccessResponse response) async {
    try {
      final verify = _functions.httpsCallable('verifyRazorpayPayment');
      await verify.call({
        'taskId': _taskId,
        'givenRating': _givenRating,
        'razorpayOrderId': response.orderId,
        'razorpayPaymentId': response.paymentId,
        'razorpaySignature': response.signature,
      });
      _onSuccess?.call();
    } catch (e, st) {
      // The most serious payment problem: money was taken but the task was not
      // closed. Keep the Razorpay ids so the owner can reconcile it by hand.
      ErrorLogger.instance.log(
        error: e,
        stack: st,
        category: 'payment',
        severity: 'fatal',
        context: 'Razorpay: paid but NOT confirmed by the server',
        taskId: _taskId,
        extra: {
          'razorpayPaymentId': response.paymentId ?? '',
          'razorpayOrderId': response.orderId ?? '',
        },
      );
      _onError?.call('Payment succeeded but could not be confirmed: $e');
    }
  }

  void _handleError(PaymentFailureResponse response) {
    // code 0 is the user closing the checkout; that is not a problem to record.
    if (response.code != Razorpay.PAYMENT_CANCELLED) {
      ErrorLogger.instance.log(
        error: 'Razorpay payment failed (code ${response.code}): ${response.message ?? 'no message'}',
        category: 'payment',
        severity: 'warning',
        context: 'Razorpay: checkout failed',
        taskId: _taskId,
      );
    }
    _onError?.call(response.message ?? 'Payment failed or was cancelled.');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // No-op: user picked an external wallet app; Razorpay handles that flow itself.
  }

  void dispose() {
    _razorpay.clear();
  }
}

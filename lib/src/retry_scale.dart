import 'dart:math';

enum RetryScale {
  /// Same time interval between every retry.
  constant,

  /// If interval is n, on every retry the the interval is increased by n.
  /// For example if [retryInterval] is set to 2 seconds, and 
  /// the [retries] is set to 4,  the interval for every retry is going to
  ///  be [2, 4, 6, 8]
  linear,

  /// If interval is n, on every retry the last interval is going 
  /// to be duplicated.  For example if [retryInterval] is set to 2 seconds, 
  /// and the [retries] is set to 4,  the interval for every retry is going 
  /// to be [2, 4, 8, 16] with some jitter added to the last interval.
  /// meaning that the interval for the last retry will be 16 + 0.5 * 2 = 18
  exponential;

  Duration getInterval(int retry, int retryInterval, {double jitter = 0.5}) {
    // Base interval calculation without jitter. This interval is determined by 
    //the retryInterval argument  and the current retry attempt, adjusted based 
    //on the retry strategy (constant, linear, or exponential).
    var baseInterval = retryInterval;

    // If the retryInterval is set to 0, immediately return a zero duration, 
    //indicating no delay.
    if (retryInterval == 0) return Duration.zero;

    // If this is not the first retry attempt, calculate the base interval based
    // on the retry scale.
    if (retry > 0) {
      switch (this) {
        case RetryScale.constant:
          // For constant scale, the interval remains the same as
          // the initial retryInterval.
          break;
        case RetryScale.linear:
          // For linear scale, the interval increases linearly with each retry.
          // The interval for the nth retry is n times the retryInterval.
          baseInterval = (retry + 1) * retryInterval;
        case RetryScale.exponential:
          // For exponential scale, the interval doubles with each retry.
          // The interval for the nth retry is 2^(n-1) times the retryInterval.
          baseInterval = retryInterval * pow(2, retry).toInt();
      }
    }

    // Adding jitter to the base interval to prevent thundering herd problem
    // and to spread out the retry attempts.
    // Jitter is added as a random fraction of the baseInterval,
    // controlled by the jitter argument.
    final random = Random();
    // The jitterValue is calculated by first generating a random number
    // between -1 and 1, scaling it by the jitter factor, and then adjusting 
    // the base interval by this amount. This introduces randomness to the 
    //retry intervals, making them less predictable.
    final jitterValue =
        (1 + jitter * (2 * random.nextDouble() - 1)) * baseInterval;

    // The final interval is the base interval adjusted by the 
    // calculated jitterValue. The max function ensures that the 
    //interval is not negative.
    return Duration(seconds: max(0, jitterValue.toInt()));
  }
}

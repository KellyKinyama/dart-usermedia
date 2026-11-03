/// Ported from pion/mediadevices `pkg/prop` constraint types
/// (int.go, float.go, string.go, bool.go, duration.go, frameformat.go).
///
/// Each constraint reports a W3C fitness-distance `compare(actual)` returning
/// `(distance, feasible)`: lower distance is a better match; `feasible == false`
/// means the actual value violates the constraint. `value()` returns the
/// constraint's resolved concrete value when it has one.
library;

import 'dart:math' as math;

import '../frame/format.dart';

/// Result of comparing a desired constraint against an actual value.
typedef Compare = (double distance, bool feasible);

double _ratio(num a, num i) {
  final denom = math.max(a.abs(), i.abs());
  if (denom == 0) return 0; // both zero -> perfect match, avoid 0/0.
  return (a - i).abs() / denom;
}

// --- Int ---------------------------------------------------------------------

abstract interface class IntConstraint {
  Compare compare(int actual);

  /// Resolved value, if this constraint pins one. `(value, false)` when not.
  (int, bool) value();
}

/// Ideal int: any value accepted, closest to [ideal] preferred.
class IntIdeal implements IntConstraint {
  const IntIdeal(this.ideal);
  final int ideal;
  @override
  Compare compare(int actual) => (_ratio(actual, ideal), true);
  @override
  (int, bool) value() => (ideal, true);
}

/// Exact int: only [exact] accepted.
class IntExact implements IntConstraint {
  const IntExact(this.exact);
  final int exact;
  @override
  Compare compare(int actual) => actual == exact ? (0, true) : (1, false);
  @override
  (int, bool) value() => (exact, true);
}

/// One-of int: any value in [options] accepted.
class IntOneOf implements IntConstraint {
  const IntOneOf(this.options);
  final List<int> options;
  @override
  Compare compare(int actual) =>
      options.contains(actual) ? (0, true) : (1, false);
  @override
  (int, bool) value() => (0, false);
}

/// Ranged int. A zero bound means "unspecified". When [ideal] is non-zero the
/// closest value to it is preferred within the range.
class IntRanged implements IntConstraint {
  const IntRanged({this.min = 0, this.max = 0, this.ideal = 0});
  final int min;
  final int max;
  final int ideal;

  @override
  Compare compare(int actual) {
    if (min != 0 && min > actual) return (1, false);
    if (max != 0 && max < actual) return (1, false);
    if (ideal == 0) return (0, true);
    if (actual == ideal) return (0, true);
    if (actual < ideal) {
      if (min == 0) return (0, true);
      return ((ideal - actual) / (ideal - min), true);
    }
    if (max == 0) return (0, true);
    return ((actual - ideal) / (max - ideal), true);
  }

  @override
  (int, bool) value() => (0, false);
}

// --- Double (Go float32/FloatConstraint) -------------------------------------

abstract interface class FloatConstraint {
  Compare compare(double actual);
  (double, bool) value();
}

class FloatIdeal implements FloatConstraint {
  const FloatIdeal(this.ideal);
  final double ideal;
  @override
  Compare compare(double actual) => (_ratio(actual, ideal), true);
  @override
  (double, bool) value() => (ideal, true);
}

class FloatExact implements FloatConstraint {
  const FloatExact(this.exact);
  final double exact;
  @override
  Compare compare(double actual) => actual == exact ? (0, true) : (1, false);
  @override
  (double, bool) value() => (exact, true);
}

class FloatOneOf implements FloatConstraint {
  const FloatOneOf(this.options);
  final List<double> options;
  @override
  Compare compare(double actual) =>
      options.contains(actual) ? (0, true) : (1, false);
  @override
  (double, bool) value() => (0, false);
}

class FloatRanged implements FloatConstraint {
  const FloatRanged({this.min = 0, this.max = 0, this.ideal = 0});
  final double min;
  final double max;
  final double ideal;

  @override
  Compare compare(double actual) {
    if (min != 0 && min > actual) return (1, false);
    if (max != 0 && max < actual) return (1, false);
    if (ideal == 0) return (0, true);
    if (actual == ideal) return (0, true);
    if (actual < ideal) {
      if (min == 0) return (0, true);
      return ((ideal - actual) / (ideal - min), true);
    }
    if (max == 0) return (0, true);
    return ((actual - ideal) / (max - ideal), true);
  }

  @override
  (double, bool) value() => (0, false);
}

// --- String ------------------------------------------------------------------

abstract interface class StringConstraint {
  Compare compare(String actual);
  (String, bool) value();
}

/// Ideal string: match preferred but a mismatch is still feasible (as in pion).
class StringIdeal implements StringConstraint {
  const StringIdeal(this.ideal);
  final String ideal;
  @override
  Compare compare(String actual) => actual == ideal ? (0, true) : (1, true);
  @override
  (String, bool) value() => (ideal, true);
}

class StringExact implements StringConstraint {
  const StringExact(this.exact);
  final String exact;
  @override
  Compare compare(String actual) => actual == exact ? (0, true) : (1, false);
  @override
  (String, bool) value() => (exact, true);
}

class StringOneOf implements StringConstraint {
  const StringOneOf(this.options);
  final List<String> options;
  @override
  Compare compare(String actual) =>
      options.contains(actual) ? (0, true) : (1, false);
  @override
  (String, bool) value() => ('', false);
}

// --- Bool --------------------------------------------------------------------

abstract interface class BoolConstraint {
  Compare compare(bool actual);
  bool value();
}

/// Exact bool: a mismatch is infeasible.
class BoolExact implements BoolConstraint {
  const BoolExact(this.exact);
  final bool exact;
  @override
  Compare compare(bool actual) => actual == exact ? (0, true) : (1, false);
  @override
  bool value() => exact;
}

/// Ideal bool: a mismatch is still feasible (just a worse fit).
class BoolIdeal implements BoolConstraint {
  const BoolIdeal(this.ideal);
  final bool ideal;
  @override
  Compare compare(bool actual) {
    final (d, _) = BoolExact(ideal).compare(actual);
    return (d, true);
  }

  @override
  bool value() => ideal;
}

// --- Duration ----------------------------------------------------------------

abstract interface class DurationConstraint {
  Compare compare(Duration actual);
  (Duration, bool) value();
}

class DurationIdeal implements DurationConstraint {
  const DurationIdeal(this.ideal);
  final Duration ideal;
  @override
  Compare compare(Duration actual) =>
      (_ratio(actual.inMicroseconds, ideal.inMicroseconds), true);
  @override
  (Duration, bool) value() => (ideal, true);
}

class DurationExact implements DurationConstraint {
  const DurationExact(this.exact);
  final Duration exact;
  @override
  Compare compare(Duration actual) =>
      actual == exact ? (0, true) : (1, false);
  @override
  (Duration, bool) value() => (exact, true);
}

class DurationRanged implements DurationConstraint {
  const DurationRanged({
    this.min = Duration.zero,
    this.max = Duration.zero,
    this.ideal = Duration.zero,
  });
  final Duration min;
  final Duration max;
  final Duration ideal;

  @override
  Compare compare(Duration actual) {
    final a = actual.inMicroseconds;
    final lo = min.inMicroseconds;
    final hi = max.inMicroseconds;
    final id = ideal.inMicroseconds;
    if (lo != 0 && lo > a) return (1, false);
    if (hi != 0 && hi < a) return (1, false);
    if (id == 0) return (0, true);
    if (a == id) return (0, true);
    if (a < id) {
      if (lo == 0) return (0, true);
      return ((id - a) / (id - lo), true);
    }
    if (hi == 0) return (0, true);
    return ((a - id) / (hi - id), true);
  }

  @override
  (Duration, bool) value() => (Duration.zero, false);
}

// --- FrameFormat -------------------------------------------------------------

abstract interface class FrameFormatConstraint {
  Compare compare(FrameFormat actual);
  (FrameFormat, bool) value();
}

/// Ideal frame format: match preferred, mismatch still feasible (as in pion).
class FrameFormatIdeal implements FrameFormatConstraint {
  const FrameFormatIdeal(this.ideal);
  final FrameFormat ideal;
  @override
  Compare compare(FrameFormat actual) =>
      actual == ideal ? (0, true) : (1, true);
  @override
  (FrameFormat, bool) value() => (ideal, true);
}

class FrameFormatExact implements FrameFormatConstraint {
  const FrameFormatExact(this.exact);
  final FrameFormat exact;
  @override
  Compare compare(FrameFormat actual) =>
      actual == exact ? (0, true) : (1, false);
  @override
  (FrameFormat, bool) value() => (exact, true);
}

class FrameFormatOneOf implements FrameFormatConstraint {
  const FrameFormatOneOf(this.options);
  final List<FrameFormat> options;
  @override
  Compare compare(FrameFormat actual) =>
      options.contains(actual) ? (0, true) : (1, false);
  @override
  (FrameFormat, bool) value() => (FrameFormat.unknown, false);
}

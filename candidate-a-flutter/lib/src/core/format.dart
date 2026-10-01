// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Deterministic presentation helpers shared by every screen (no device time zone or locale involved).
import 'bundle_data.dart';
import 'steps.dart';
import 'strings.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// UTC calendar date "YYYY-MM-DD" of epoch milliseconds.
String isoDate(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
  return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
}

/// ISO weekday (1 = Monday) of the date part of "YYYY-MM-DDTHH:MM:SS+03:00" (the schedule's own fixed offset).
int weekdayOf(String iso) {
  final y = int.parse(iso.substring(0, 4)), m = int.parse(iso.substring(5, 7)), d = int.parse(iso.substring(8, 10));
  return DateTime.utc(y, m, d).weekday;
}

String hhmm(String iso) => iso.substring(11, 16);

String scheduleItem(Strings s, ScheduleEntry e) => s.t('details.schedule.item', {
      'label': s.lang == 'ar' ? e.labelAr : e.labelEn,
      'day': s.t('day.${weekdayOf(e.start)}'),
      'start': hhmm(e.start),
      'end': hhmm(e.end),
    });

String stepText(Strings s, RouteStep st) {
  switch (st.kind) {
    case 'walk':
      return s.t('route.step.walk', {'length': st.m});
    case 'stairs':
      return s.t('route.step.stairs', {'floor': st.floor});
    case 'elevator':
      return s.t('route.step.elevator', {'floor': st.floor});
    case 'exit':
      return s.t('route.step.exit', {'building': st.building});
    case 'enter':
      return s.t('route.step.enter', {'building': st.building});
    default:
      return s.t('route.step.arrive', {'code': st.code});
  }
}

String summaryText(Strings s, RouteSummary m) =>
    s.t('route.summary', {'length': m.lengthM, 'steps': m.steps, 'floors': m.floors});

String rejectText(Strings s, String outcome) {
  switch (outcome) {
    case 'REJECT_STEP_FREE_UNAVAILABLE':
      return s.t('route.reject.stepfree');
    case 'REJECT_BLOCKED':
      return s.t('route.reject.blocked');
    case 'REJECT_UNREACHABLE':
      return s.t('route.reject.unreachable');
    case 'REJECT_UNTRUSTED':
      return s.t('route.reject.untrusted');
    default:
      return s.t('route.reject.unknown');
  }
}

/// Trust/offline status line for a bundle info object of the common module.
String trustText(Strings s, Map<String, Object?>? info) {
  final state = info?['state'] as String?;
  switch (state) {
    case 'VALID':
      return s.t('trust.status.valid', {'version': info!['version'], 'until': isoDate(info['valid_until_ms'] as int)});
    case 'EXPIRED':
      return s.t('trust.status.expired');
    case 'TIME_UNTRUSTED':
      return s.t('trust.status.time_untrusted');
    case 'NOT_YET_VALID':
      return s.t('trust.status.not_yet_valid');
    case 'INVALID':
      return s.t('trust.status.invalid');
    default:
      return s.t('trust.status.none');
  }
}

String qrText(Strings s, Map<String, Object?> outcome) {
  switch (outcome['outcome']) {
    case 'IDENTITY_VALID':
      return s.t('qr.identity', {
        'anchor': outcome['anchor'],
        'building': outcome['building'],
        'floor': outcome['floor'],
        'kind': s.t('kind.${outcome['kind']}'),
      });
    case 'REJECT_BAD_SIGNATURE':
      return s.t('qr.reject.signature');
    case 'REJECT_EXPIRED':
      return s.t('qr.reject.expired');
    case 'REJECT_FOREIGN_PAYLOAD':
      return s.t('qr.reject.foreign');
    case 'REJECT_UNKNOWN_ANCHOR':
      return s.t('qr.reject.unknown');
    case 'REJECT_BUNDLE_MISMATCH':
      return s.t('qr.reject.bundle');
    case 'REJECT_UNTRUSTED_TIME':
      return s.t('qr.reject.time');
    case 'REJECT_NO_BUNDLE':
      return s.t('qr.reject.nobundle');
    case 'CAMERA_UNAVAILABLE':
      return s.t('qr.camera.unavailable');
    case 'PERMISSION_DENIED':
      return s.t('qr.camera.denied');
    case 'CANCELLED':
      return s.t('qr.cancelled');
    default:
      return s.t('qr.reject.malformed');
  }
}

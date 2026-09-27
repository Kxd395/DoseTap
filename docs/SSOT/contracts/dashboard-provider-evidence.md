# Nearby Apple Health sleep evidence

DOSETAP-76. This is a read-only reporting packet, not a clinical database import,
reviewed sleep total, cloud upload or backup. WHOOP remains separately unavailable.

The phone offers an unchecked, connection-scoped choice to include the previous
30 elapsed days of Apple Health sleep samples. Preparation occurs before nearby
advertising, outside the report request deadline. It requires the existing Health
integration preference; opening the screen does not request permission or query.
Failure is explicit and does not silently publish a provider-free success. The
owner may turn the choice off to send local records only. Leaving/backgrounding,
cancelling or changing the choice invalidates late preparation results.

The appleHealth section contains one version-1 query packet, including query start,
end, completion, phone timezone and original SleepEvidenceSample values. Section
rowCount is the packet count, not the sample/night count. A successful empty query
is zero readable samples, not no sleep or verified permission. Legacy unavailable
sections and empty arrays stay readable, without claiming a completed query.

Range is at most 30 * 86,400 seconds. The adapter requests at most 10,001 samples;
more than 10,000 rejects preparation instead of truncating. Original overlapping
boundaries, UUID, category, stage and allowed source/device metadata are retained;
no hardware identifiers or arbitrary metadata are copied. Unknown categories stay
unknown. Invalid/future bounds, inconsistent stage/category, absent/duplicate sample
IDs, nonoverlapping samples, invalid timezone and unsupported versions reject the
packet. Completion must precede the local snapshot capture. All provider fields
are validated before replacing the iPad cache, including on reopening.

Provider preparation and local SQLite capture have separate timestamps. The full
encoded snapshot must fit the existing 32 MiB transport bound including base64;
an oversize report fails without dropping rows. Repeated refresh during one
connection uses the same visibly dated provider preparation with fresh local
records. Start a new connection to refresh provider evidence.

The iPad displays query status/range/timezone, sample and source counts and original
stage intervals grouped for inspection by calendar day. Overlaps are not summed;
in-bed is not asleep, unknown gaps are not awake, and source disagreement is not
resolved by a display color. This first transfer does not enable dose-to-sleep,
return-to-sleep or treatment-night sleep averages. Those need reviewed boundaries,
source consensus, metric eligibility and separate native/device acceptance.

Tests: DashboardSleepEvidenceTests, DashboardModelTests, HealthKitAndAPITests and
native publisher/provider evidence journeys. Live Health permission/source parity,
physical transfer performance, VoiceOver, privacy/security and release remain gates.

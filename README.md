# Meeting Review Agent

An AI-powered daily meeting analysis tool that fetches meetings from Fireflies, clusters them by type, grades them using weighted rubrics, & generates actionable improvement recommendations.

## Features

- **Automatic Meeting Clustering** : Categorizes meetings into Internal, 1:1, Pitch, Interview, or Other
- **Weighted Grading Rubrics** : Each meeting type has specific criteria with importance weights
- **AI-Powered Analysis** : Uses an LLM to evaluate transcripts against rubrics
- **Daily Reports** : Generates markdown reports with scores & improvement recommendations
- **Scheduled Execution** : Runs daily via launchd (macOS) or cron

## Meeting Types & Rubrics

### Internal Meetings
- Agenda clarity (20%)
- Decision outcomes (25%)
- Action items (25%)
- Time efficiency (15%)
- Participation balance (15%)

### 1:1 Meetings
- Career development (25%)
- Feedback exchange (25%)
- Blockers addressed (20%)
- Relationship building (15%)
- Action items (15%)

### Pitch Meetings
- Problem understanding (15%)
- Solution clarity (15%)
- Market opportunity (10%)
- Team assessment (15%)
- Traction evidence (10%)
- Listening quality (10%)
- Question depth (10%)
- Reflection quality (5%)
- Immediate value delivery (5%)
- Relevance mapping (5%)
- Insight capture (5%)
- Red flag detection (5%)
- Next steps clarity (5%)

### Interview Meetings
- Role clarity (15%)
- Skill assessment (25%)
- Culture fit (20%)
- Candidate engagement (15%)
- Structured evaluation (15%)
- Next steps clarity (10%)

## Usage

```bash
# Run for today
ruby meeting_review_daily.rb

# Run for specific date
ruby meeting_review_daily.rb 2026-01-27
```

## Configuration

Before running, update the following in `meeting_review_daily.rb` :

1. **YOUR_NAMES** : Set to your name variations for meeting filtering
2. **INTERNAL_PARTICIPANTS** : Set to your internal team members
3. **API paths** : Update the `EXECUTE_PATH` to point to your Code Mode executor (or replace with direct API calls)

## Output

Reports are saved to `reports/YYYY-MM-DD-meeting-review.md` with :
- Executive summary (meeting counts by type)
- Daily weighted average score
- Per-meeting scores by criterion
- Prioritized improvement recommendations

## Dependencies

- Ruby
- Fireflies API access (for meeting transcripts)
- An LLM API (Gemini, Claude, or similar) for transcript analysis

## Scheduled Execution

Example launchd plist (macOS) :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.meeting-review</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ruby</string>
        <string>/path/to/meeting_review_daily.rb</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>20</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

## License

MIT

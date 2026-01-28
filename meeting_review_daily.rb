#!/usr/bin/env ruby

require 'date'
require 'json'
require 'net/http'
require 'securerandom'
require 'uri'

# ============================================================
# CONFIGURATION - Update these for your setup
# ============================================================

# Path to your LLM executor (or replace with direct API calls)
EXECUTE_PATH = ENV['MEETING_REVIEW_EXECUTE_PATH'] || '/usr/local/bin/execute'

# Your name variations for filtering meetings
YOUR_NAMES = ['your_name', 'your_nickname']

# Internal team members for clustering
INTERNAL_PARTICIPANTS = ['teammate1', 'teammate2', 'team@company.com']

# Meeting type detection keywords
PITCH_KEYWORDS = ['pitch', 'founder', 'startup', 'deck', 'demo', 'fundraising', 'investment']
ONE_ON_ONE_KEYWORDS = ['1:1', '1-1', 'one on one', '1 on 1', '<>', 'sync', 'check-in', 'weekly']
INTERVIEW_KEYWORDS = ['interview', 'candidate', 'hiring', 'recruiting']

# ============================================================
# API WRAPPERS - Replace with your preferred API integration
# ============================================================

class FirefliesAPI
  MAX_RETRIES = 1
  RETRY_DELAY = 2

  def self.list_recent(limit: 10, format: :detailed)
    with_retry do
      system("#{EXECUTE_PATH} --code 'FirefliesAPI.list_recent(limit: #{limit})' > /tmp/fireflies_output.json 2>&1")
      JSON.parse(File.read('/tmp/fireflies_output.json'), symbolize_names: true)
    end
  end

  def self.get_transcript(transcript_id:, format: :detailed)
    with_retry do
      system("#{EXECUTE_PATH} --code 'FirefliesAPI.get_transcript(transcript_id: \"#{transcript_id}\")' > /tmp/transcript_output.json 2>&1")
      JSON.parse(File.read('/tmp/transcript_output.json'), symbolize_names: true)
    end
  end

  private

  def self.with_retry
    retries = 0
    begin
      yield
    rescue => e
      if retries < MAX_RETRIES
        retries += 1
        sleep(RETRY_DELAY)
        retry
      end
      { success: false, error: e.message }
    end
  end
end

class LLMAnalyzer
  MAX_RETRIES = 1
  RETRY_DELAY = 2

  def self.analyze(prompt:, max_tokens: 1500)
    retries = 0
    begin
      prompt_file = "/tmp/llm_prompt_#{$$}_#{SecureRandom.hex(6)}.txt"
      File.write(prompt_file, prompt)

      cmd = "#{EXECUTE_PATH} --code 'GeminiAPI.generate(max_tokens: #{max_tokens})' --body-file '#{prompt_file}' 2>&1"
      output = `#{cmd}`

      File.delete(prompt_file) rescue nil

      result = JSON.parse(output, symbolize_names: true)

      if result[:success]
        result[:content] || result.to_s
      else
        raise "LLM error : #{result[:error]}"
      end
    rescue => e
      if retries < MAX_RETRIES
        retries += 1
        sleep(RETRY_DELAY)
        retry
      end
      puts "LLM error : #{e.message}"
      "Unable to analyze : #{e.message}"
    end
  end
end

# ============================================================
# HELPERS
# ============================================================

def calculate_weighted_score(grades, rubric)
  total_weight = 0
  weighted_sum = 0
  grades.each do |criterion, details|
    criterion_str = criterion.to_s
    weight = rubric.dig(criterion_str, :weight) || rubric.dig(criterion_str.gsub('_', ' '), :weight) || 10
    if details[:score]
      weighted_sum += details[:score] * weight
      total_weight += weight
    end
  end
  total_weight > 0 ? (weighted_sum.to_f / total_weight).round(1) : 0
end

# ============================================================
# GRADING RUBRICS
# ============================================================

RUBRICS = {
  internal: {
    'Agenda clarity' => { question: 'Was there a clear agenda distributed beforehand with specific objectives?', weight: 20 },
    'Decision outcomes' => { question: 'Were concrete decisions made with clear ownership assigned?', weight: 25 },
    'Action items' => { question: 'Were specific next steps identified with owners & deadlines?', weight: 25 },
    'Time efficiency' => { question: 'Did the meeting start/end on time & stay focused on agenda?', weight: 15 },
    'Participation balance' => { question: 'Did all attendees contribute meaningfully (balanced talk-time)?', weight: 15 }
  },
  pitch: {
    'Problem understanding' => { question: 'Did we deeply understand the problem being solved & customer pain?', weight: 13 },
    'Solution clarity' => { question: 'Was the solution clearly explained with differentiation from alternatives?', weight: 13 },
    'Market opportunity' => { question: 'Was TAM/SAM/SOM articulated with credible sizing methodology?', weight: 9 },
    'Team assessment' => { question: 'Did we evaluate founder-market fit, relevant experience & team dynamics?', weight: 13 },
    'Traction evidence' => { question: 'Were concrete metrics shared (ARR, growth rate, retention)?', weight: 9 },
    'Listening quality' => { question: 'Did the interviewer allow adequate founder speaking time (~70%) with minimal interruptions & relevant follow-ups?', weight: 9 },
    'Question depth' => { question: 'Did questions go 2-3 levels deep on critical topics with strategic "why" follow-ups?', weight: 9 },
    'Reflection quality' => { question: 'Did the interviewer paraphrase or reflect back founder\'s key points before responding? (Target : 2+ instances)', weight: 4 },
    'Immediate value delivery' => { question: 'Did the interviewer offer specific intros, insights, or resources during the call? (Target : 1+ concrete offer)', weight: 4 },
    'Relevance mapping' => { question: 'Did the interviewer explicitly connect portfolio/expertise to founder\'s current challenges?', weight: 4 },
    'Insight capture' => { question: 'Were key non-obvious insights documented & next steps clearly defined with specific actions?', weight: 4 },
    'Red flag detection' => { question: 'Were potential risks assessed (founder coachability, team alignment, market depth)?', weight: 5 },
    'Next steps clarity' => { question: 'Were follow-up actions & timeline clearly established?', weight: 4 }
  },
  one_on_one: {
    'Career development' => { question: 'Was meaningful career growth or skill development discussed?', weight: 25 },
    'Feedback exchange' => { question: 'Was bidirectional feedback shared constructively?', weight: 25 },
    'Blockers addressed' => { question: 'Were obstacles & challenges identified with solutions proposed?', weight: 20 },
    'Relationship building' => { question: 'Did the meeting strengthen trust & working relationship?', weight: 15 },
    'Action items' => { question: 'Were specific follow-up items identified with ownership?', weight: 15 }
  },
  interview: {
    'Role clarity' => { question: 'Was the role & expectations clearly communicated?', weight: 15 },
    'Skill assessment' => { question: 'Were relevant skills & experience thoroughly evaluated?', weight: 25 },
    'Culture fit' => { question: 'Was alignment with company values & team dynamics assessed?', weight: 20 },
    'Candidate engagement' => { question: 'Did the candidate have opportunity to ask questions & learn about the role?', weight: 15 },
    'Structured evaluation' => { question: 'Was a consistent evaluation framework applied?', weight: 15 },
    'Next steps clarity' => { question: 'Were timeline & next steps clearly communicated to candidate?', weight: 10 }
  },
  other: {
    'Objective achievement' => { question: 'Did the meeting achieve its stated objective?', weight: 35 },
    'Information exchange' => { question: 'Was valuable, actionable information shared?', weight: 25 },
    'Relationship building' => { question: 'Did the meeting strengthen professional relationships?', weight: 20 },
    'Follow-up clarity' => { question: 'Were any follow-up items clearly identified?', weight: 20 }
  }
}

# ============================================================
# MEETING CLUSTERING
# ============================================================

def cluster_meeting(meeting)
  participants_str = (meeting[:participants] || []).join(' ').downcase
  title = (meeting[:title] || '').downcase

  if INTERVIEW_KEYWORDS.any? { |k| title.include?(k) }
    return { cluster: :interview, confidence: :high }
  end

  if PITCH_KEYWORDS.any? { |k| title.include?(k) }
    return { cluster: :pitch, confidence: :high }
  end

  if ONE_ON_ONE_KEYWORDS.any? { |k| title.include?(k) }
    if INTERNAL_PARTICIPANTS.any? { |p| participants_str.include?(p) }
      return { cluster: :one_on_one, confidence: :high }
    end
    return { cluster: :other, confidence: :medium }
  end

  if INTERNAL_PARTICIPANTS.any? { |p| participants_str.include?(p) }
    return { cluster: :internal, confidence: :high }
  end

  { cluster: :other, confidence: :medium }
end

# ============================================================
# GRADING
# ============================================================

def extract_json(text)
  # Find matching braces to extract the outermost JSON object
  start_idx = text.index('{')
  return nil unless start_idx

  depth = 0
  (start_idx...text.length).each do |i|
    case text[i]
    when '{'
      depth += 1
    when '}'
      depth -= 1
      if depth == 0
        return text[start_idx..i]
      end
    end
  end
  nil
end

def grade_meeting(meeting, transcript, cluster)
  rubric = RUBRICS[cluster]

  rubric_str = rubric.map do |criterion, details|
    "- #{criterion} (#{details[:weight]}% weight) : #{details[:question]}"
  end.join("\n")

  prompt = <<~PROMPT
    Analyze this meeting transcript & grade it using the following weighted rubric.
    For each criterion, provide :
    1. Score (1-10)
    2. Brief evidence (quote from transcript if applicable)
    3. One-sentence justification

    Meeting : #{meeting[:title]}
    Meeting Type : #{cluster}

    Rubric (with weights) :
    #{rubric_str}

    Transcript :
    #{transcript[:text]}

    Format your response as JSON :
    {
      "criterion_name": {
        "score": 7,
        "evidence": "Quote or observation",
        "justification": "Why this score"
      }
    }

    IMPORTANT : Use the exact criterion names from the rubric as keys.
  PROMPT

  result = LLMAnalyzer.analyze(prompt: prompt)

  begin
    json_str = extract_json(result)
    json_str ? JSON.parse(json_str, symbolize_names: true) : {}
  rescue JSON::ParserError
    puts "Warning : Could not parse grading JSON for #{meeting[:title]}"
    {}
  end
end

# ============================================================
# IMPROVEMENT RECOMMENDATIONS
# ============================================================

def generate_improvements(meeting, grades, cluster)
  rubric = RUBRICS[cluster]
  low_scores = grades.select { |k, v| v[:score] && v[:score] < 7 }

  if low_scores.empty?
    return ["Meeting performed well across all criteria. Continue current approach."]
  end

  weighted_avg = calculate_weighted_score(grades, rubric)

  prioritized_low = low_scores.sort_by do |k, v|
    criterion_str = k.to_s
    weight = rubric.dig(criterion_str, :weight) || rubric.dig(criterion_str.gsub('_', ' '), :weight) || 10
    -weight
  end

  prompt = <<~PROMPT
    This #{cluster} meeting had a weighted average score of #{weighted_avg}/10.

    Low-scoring criteria (prioritized by importance) :
    #{prioritized_low.map { |k, v|
      criterion_str = k.to_s
      weight = rubric.dig(criterion_str, :weight) || rubric.dig(criterion_str.gsub('_', ' '), :weight) || 10
      "- #{k} (#{weight}% weight) : #{v[:score]}/10 - #{v[:justification]}"
    }.join("\n")}

    Provide 3-5 specific, actionable recommendations to improve future #{cluster} meetings.
    Focus on what the participant can do differently (preparation, questions to ask, structure).
    Prioritize recommendations that address higher-weighted criteria.

    Format as a numbered list.
  PROMPT

  result = LLMAnalyzer.analyze(prompt: prompt)
  result.split("\n").select { |line| line.match?(/^\d+\./) }.map(&:strip)
end

# ============================================================
# REPORT GENERATION
# ============================================================

def generate_report(meetings_by_cluster, date)
  report = ["# Daily Meeting Review : #{date}", "", "## Executive Summary"]

  total = meetings_by_cluster.values.flatten.count
  report << "- Total meetings : #{total}"
  report << "- Internal : #{meetings_by_cluster[:internal]&.count || 0}"
  report << "- 1:1s : #{meetings_by_cluster[:one_on_one]&.count || 0}"
  report << "- Pitch : #{meetings_by_cluster[:pitch]&.count || 0}"
  report << "- Interview : #{meetings_by_cluster[:interview]&.count || 0}"
  report << "- Other : #{meetings_by_cluster[:other]&.count || 0}"
  report << ""

  all_weighted_scores = []
  meetings_by_cluster.each do |cluster, meetings|
    rubric = RUBRICS[cluster]
    meetings.each do |m|
      next unless m[:grades] && !m[:grades].empty?
      score = calculate_weighted_score(m[:grades], rubric)
      all_weighted_scores << score if score > 0
    end
  end

  if all_weighted_scores.any?
    daily_avg = (all_weighted_scores.sum / all_weighted_scores.count).round(1)
    report << "**Daily Weighted Average : #{daily_avg}/10**"
    report << ""
  end

  cluster_order = [:internal, :one_on_one, :pitch, :interview, :other]
  cluster_names = {
    internal: 'Internal',
    one_on_one: '1:1',
    pitch: 'Pitch',
    interview: 'Interview',
    other: 'Other'
  }

  cluster_order.each do |cluster|
    meetings = meetings_by_cluster[cluster]
    next if meetings.nil? || meetings.empty?

    rubric = RUBRICS[cluster]
    report << "## #{cluster_names[cluster]} Meetings (#{meetings.count} total)"
    report << ""

    meetings.each do |m|
      report << "### #{m[:title]} - #{m[:date]}"
      report << "**Participants :** #{m[:participants]&.join(', ')}"
      report << "**Cluster confidence :** #{m[:cluster_info]&.[](:confidence) || 'unknown'}"
      report << ""

      if m[:grades] && !m[:grades].empty?
        weighted_avg = calculate_weighted_score(m[:grades], rubric)

        report << "**Weighted Score : #{weighted_avg}/10**"
        report << ""
        report << "**Scores by Criterion :**"
        m[:grades].each do |criterion, details|
          criterion_str = criterion.to_s
          weight = rubric.dig(criterion_str, :weight) || rubric.dig(criterion_str.gsub('_', ' '), :weight) || 10
          score = details[:score] || 'N/A'
          report << "- #{criterion} (#{weight}%) : #{score}/10"
          report << "  - #{details[:justification]}" if details[:justification]
        end
        report << ""
      end

      if m[:improvements] && !m[:improvements].empty?
        report << "**Improvements :**"
        m[:improvements].each { |imp| report << "- #{imp}" }
        report << ""
      end

      report << "---"
      report << ""
    end
  end

  report.join("\n")
end

# ============================================================
# MAIN
# ============================================================

def main(date = Date.today.to_s)
  puts "Fetching meetings for #{date}..."

  meetings_data = FirefliesAPI.list_recent(limit: 50, format: :detailed)

  if meetings_data[:success] == false
    puts "Error fetching meetings : #{meetings_data[:error]}"
    exit 1
  end

  meetings = meetings_data[:transcripts] || []

  target_date = Date.parse(date)
  daily_meetings = meetings.select do |m|
    meeting_date = m[:date] ? Date.parse(m[:date].split('T')[0]) : nil
    next false unless meeting_date == target_date

    title_lower = (m[:title] || '').downcase
    YOUR_NAMES.any? { |name| title_lower.include?(name) }
  end

  puts "Found #{daily_meetings.count} meetings for #{date}"

  if daily_meetings.empty?
    puts "No meetings found. Exiting."
    exit 0
  end

  meetings_by_cluster = { internal: [], one_on_one: [], pitch: [], interview: [], other: [] }

  daily_meetings.each do |meeting|
    meeting[:participants] = meeting[:title].split(/[<>\/]/).map(&:strip).select { |p| p.length > 2 }

    cluster_info = cluster_meeting(meeting)
    cluster = cluster_info[:cluster]

    puts "Processing : #{meeting[:title]} (#{cluster})"

    transcript_data = FirefliesAPI.get_transcript(
      transcript_id: meeting[:id],
      format: :detailed
    )

    if transcript_data[:success] == false
      puts "  Warning : Could not fetch transcript : #{transcript_data[:error]}"
      meeting[:error] = transcript_data[:error]
      meetings_by_cluster[cluster] << meeting
      next
    end

    transcript = transcript_data[:transcript] || {}

    puts "  Grading..."
    grades = grade_meeting(meeting, transcript, cluster)

    puts "  Generating improvements..."
    improvements = generate_improvements(meeting, grades, cluster)

    meeting[:cluster_info] = cluster_info
    meeting[:grades] = grades
    meeting[:improvements] = improvements

    meetings_by_cluster[cluster] << meeting
  end

  puts "\nGenerating report..."
  report = generate_report(meetings_by_cluster, date)

  reports_dir = File.join(File.dirname(__FILE__), 'reports')
  Dir.mkdir(reports_dir) unless Dir.exist?(reports_dir)

  report_path = File.join(reports_dir, "#{date}-meeting-review.md")
  File.write(report_path, report)

  puts "\nReport saved to : #{report_path}"
  puts "\n#{report}"
end

# Run with today's date or provided date
date = ARGV[0] || Date.today.to_s
main(date)

# frozen_string_literal: true

class MeetingsController < ApplicationController
  def index
    @meetings = Meeting.all
    @system_data = Rails.cache.fetch('system_data') do
      JSON.parse(File.read(Rails.root.join("data/system_data.json")))
    rescue Errno::ENOENT, JSON::ParserError => e
      Rails.logger.error("MeetingsController#index: Failed to load system_data - #{e.message}")
      { "bodies" => [] }  # Return empty structure to prevent crashes
    end
  end

  def new
    @meeting = Meeting.new
    @bodies = extract_bodies_from_system
  end

  def create
    @meeting = create_or_update_meeting
    redirect_to meetings_path, notice: "Schůzka naplánována."
  end

  def edit
    @meeting = Meeting.find(params[:id])
    @bodies = extract_bodies_from_system
  end

  def update
    @meeting = Meeting.find(params[:id])
    create_or_update_meeting  # vytvoříme nový z dat formuláře
    @meeting.destroy  # smažeme původní záznam
    redirect_to meetings_path, notice: "Schůzka upravena."
  end

  def destroy
    @meeting = Meeting.find(params[:id])
    @meeting.destroy
    redirect_to meetings_path, notice: "Schůzka smazána."
  end

  private

  def extract_bodies_from_system
    system_data = Rails.cache.fetch('system_data') do
      JSON.parse(File.read(Rails.root.join("data/system_data.json")))
    rescue Errno::ENOENT, JSON::ParserError => e
      Rails.logger.error("MeetingsController#extract_bodies_from_system: Failed to load system_data - #{e.message}")
      { "bodies" => [] }
    end
    system_data["bodies"].map { |b| b["name"] }
  end

  # Strong parameters - whitelist only permitted attributes
  def meeting_params
    params.require(:meeting).permit(:start_time, :end_time, :topic)
  rescue ActionController::ParameterMissing
    {}
  end

  # Whitelist participants array
  def participants_params
    if params[:participants].is_a?(Array)
      params[:participants]
    elsif params[:meeting] && params[:meeting][:participants].is_a?(Array)
      params[:meeting][:participants]
    else
      []
    end
  end

  def create_or_update_meeting
    # Use strong parameters to extract only permitted attributes
    permitted_params = meeting_params
    participants = participants_params

    start_time = permitted_params[:start_time]
    end_time = permitted_params[:end_time]
    topic = permitted_params[:topic] || ""
  
    system_data = Rails.cache.fetch('system_data') do
      JSON.parse(File.read(Rails.root.join("data/system_data.json")))
    rescue Errno::ENOENT, JSON::ParserError => e
      Rails.logger.error("MeetingsController#create_or_update_meeting: Failed to load system_data - #{e.message}")
      { "bodies" => [] }
    end
    bodies = system_data["bodies"]
  
    parsed_participants = participants.map { |name| find_body(name, bodies) }.compact
    if parsed_participants.size < 2
      redirect_to new_meeting_path, alert: "Musíš vybrat alespoň dvě tělesa." and return
    end
  
    universal_duration = time_diff(start_time, end_time)
  
    local_durations = parsed_participants.map do |p|
      universal_duration * p["dilation"]
    end
  
    distances = []
    parsed_participants.combination(2) do |a, b|
      distances << distance(a, b)
    end
  
    avg_duration = (local_durations.sum / local_durations.size.to_f).round(2)
    avg_delay = ((distances.sum / distances.size.to_f) / 100).round(2)

    meeting = Meeting.create!(
      start_time: start_time,
      end_time: end_time,
      topic: topic,
      participants: participants.to_json,
      local_avg_duration: avg_duration,
      avg_delay: avg_delay
    )

    meeting
  end
  

  def find_body(name, bodies)
    bodies.find { |b| b["name"].downcase == name.downcase }
  end

  def distance(b1, b2)
    dx = b1["x"] - b2["x"]
    dy = b1["y"] - b2["y"]
    Math.sqrt(dx**2 + dy**2)
  end

  def time_diff(start_str, end_str)
    s_h, s_m = start_str.split(":").map(&:to_i)
    e_h, e_m = end_str.split(":").map(&:to_i)
  
    start_minutes = s_h * 60 + s_m
    end_minutes = e_h * 60 + e_m
  
    diff = end_minutes - start_minutes
    diff += 24 * 60 if diff < 0  # přechod přes půlnoc
  
    diff
  end
end


class MeetingsController < ApplicationController
  def index
    @meetings = Meeting.all
    @system_data = JSON.parse(File.read(Rails.root.join("data/system_data.json")))
  end

  def new
    @meeting = Meeting.new
    @bodies = extract_bodies_from_system
  end

  def create
    create_or_update_meeting
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
    system_data = JSON.parse(File.read(Rails.root.join("data/system_data.json")))
    system_data["bodies"].map { |b| b["name"] }
  end


  def create_or_update_meeting
    meeting_data = params[:meeting] || {}
    participants = params[:participants] || meeting_data[:participants] || []
    
    start_time = meeting_data[:start_time] || params[:start_time]
    end_time = meeting_data[:end_time] || params[:end_time]
    topic = meeting_data[:topic] || params[:topic] || ""
  
    system_data = JSON.parse(File.read(Rails.root.join("data/system_data.json")))
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
  
    Meeting.create!(
      start_time: start_time,
      end_time: end_time,
      topic: topic,
      participants: participants.to_json,
      local_avg_duration: avg_duration,
      avg_delay: avg_delay
    )
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


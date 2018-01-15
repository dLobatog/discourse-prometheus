require 'rails_helper'
require 'prometheus_exporter/server'
require_relative '../../lib/collector'

module DiscoursePrometheus
  describe Collector do

    it "Can handle scheduled job metrics" do
      collector = Collector.new
      metric = InternalMetric::Job.new

      metric.scheduled = true
      metric.job_name = "Bob"
      metric.duration = 1.778

      collector.process(metric.to_h.to_json)
      metrics = collector.prometheus_metrics

      duration = metrics.find { |m| m.name == "scheduled_job_duration_seconds" }
      count = metrics.find { |m| m.name == "scheduled_job_count" }

      expect(duration.data).to eq({ job_name: "Bob" } => 1.778)
      expect(count.data).to eq({ job_name: "Bob" } => 1)
    end

    it "Can handle process metrics" do
      collector = Collector.new
      reporter = Reporter::Process.new(:web)
      collector.process(reporter.collect.to_h.to_json)

      metrics = collector.prometheus_metrics
      rss = metrics.find { |m| m.name == "rss" }

      expect(rss.data[type: "web", pid: Process.pid]).to be > 0
    end

    it "Can expire old metrics" do
      collector = Collector.new

      old_metric = InternalMetric::Process.new
      old_metric.pid = 100
      old_metric.rss = 100
      old_metric.major_gc_count = old_metric.minor_gc_count = old_metric.total_allocated_objects = 0
      old_metric.created_at = old_metric.created_at - 2000

      collector.process(old_metric.to_h.to_json)

      new_metric = InternalMetric::Process.new
      new_metric.pid = 200
      new_metric.rss = 20
      new_metric.major_gc_count = new_metric.minor_gc_count = new_metric.total_allocated_objects = 0

      collector.process(new_metric.to_h.to_json)

      metrics = collector.prometheus_metrics
      rss = metrics.find { |m| m.name == "rss" }

      expect(rss.data[type: nil, pid: 200]).to be > 0
      expect(rss.data.length).to eq(1)
    end

    it "Can count metrics correctly" do
      metrics = []
      metrics << InternalMetric::Web.get(tracked: true, status_code: 200, db: "bob")
      metrics << InternalMetric::Web.get(tracked: true, status_code: 200, db: "bob")
      metrics << InternalMetric::Web.get(tracked: true, logged_in: true, status_code: 200, db: "bill")
      metrics << InternalMetric::Web.get(tracked: true, mobile: true, status_code: 200, db: "jake")
      metrics << InternalMetric::Web.get(tracked: false, status_code: 200, db: "bob", user_api: true)
      metrics << InternalMetric::Web.get(tracked: false, status_code: 300, db: "bob", admin_api: true)
      metrics << InternalMetric::Web.get(tracked: false, background: true, status_code: 300, db: "bob")

      collector = Collector.new
      metrics.each do |metric|
        collector.process(metric.to_h.to_json)
      end

      exported = collector.prometheus_metrics

      page_views = exported.find { |m| m.name == "page_views" }

      expected = {
        { db: "bob", type: "anon", device: "desktop" } => 2,
        { db: "bill", type: "logged_in", device: "desktop" } => 1,
        { db: "jake", type: "anon", device: "mobile" } => 1
      }

      expect(page_views.data).to eq(expected)

      http_requests = exported.find { |m| m.name == "http_requests" }
      expected = {
        { db: "bob", api: "web", type: "regular", status: 200 } => 2,
        { db: "bill", api: "web", type: "regular", status: 200 } => 1,
        { db: "jake", api: "web", type: "regular", status: 200 } => 1,
        { db: "bob", api: "user", type: "regular", status: 200 } => 1,
        { db: "bob", api: "admin", type: "regular", status: 300 } => 1,
        { db: "bob", api: "web", type: "background", status: "-1" } => 1
      }
      expect(http_requests.data).to eq(expected)
    end
  end
end

import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.interval(
  "renew Gmail Pub/Sub watches",
  { hours: 12 },
  internal.google.renewExpiringGmailWatches,
  {},
);

export default crons;

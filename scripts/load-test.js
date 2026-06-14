// k6 load test: ramp traffic into nginx to trigger HPA scale-out.
// Run: k6 run scripts/load-test.js
// Watch pods spawn: kubectl get hpa,pods -n payments-dev -w
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "30s", target: 20 },   // ramp up — pods should still handle this
    { duration: "60s", target: 100 },  // sustained spike — HPA triggers around here
    { duration: "30s", target: 200 },  // peak — expect 4-6 pods after scale-out
    { duration: "30s", target: 0 },    // cool down — watch replicas drop after 60s
  ],
  thresholds: {
    http_req_duration: ["p(95)<500"],  // 95th-percentile latency under 500ms
    http_req_failed: ["rate<0.01"],    // less than 1% errors
  },
};

// Set via env: k6 run -e TARGET_URL=http://localhost:8080 scripts/load-test.js
const TARGET_URL = __ENV.TARGET_URL || "http://localhost:8080";

export default function () {
  const res = http.get(TARGET_URL);
  check(res, {
    "status 200": (r) => r.status === 200,
    "body contains payments": (r) => r.body.includes("payments"),
  });
  sleep(0.1);
}

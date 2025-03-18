# PCI DSS Payment Processing Backend

## ✅ Deploy

1. Add GitHub Secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. Push to `main` → triggers full CI/CD pipeline.

3. Validate:
```bash
curl http://<ALB-DNS>
# → {"status":"Payment Processed", "timestamp":"..."}



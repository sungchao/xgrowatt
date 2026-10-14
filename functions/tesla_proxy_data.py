"""
Stub module for tesla_proxy_data.
For production deployments requiring Tesla Fleet telemetry and signed commands,
compile the open-source Tesla HTTP Proxy (github.com/teslamotors/vehicle-command)
and place the binary in functions/bin/tesla-http-proxy or compress to proxy_blob.dat.
"""

PROXY_B64 = ""  # Place base64-encoded gzipped binary here if deploying to serverless without local binaries

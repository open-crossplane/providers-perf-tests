#!/usr/bin/env python3
import http.server
import socketserver
import os
'''
This needs prometheus to be running on port 9090
and updated the prometheus.yml file to scrape the metrics off of the python server
and the prometheus.yml file needs to be in the same directory as the python file
..
scrape_configs:
 - job_name: 'imported_metrics'
   static_configs:
     - targets: ['localhost:8000']
...
'''
PORT = 8000

web_dir = os.path.join(os.path.dirname(__file__), 'metrics')
os.chdir(web_dir)

Handler = http.server.SimpleHTTPRequestHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print("serving metrics at port", PORT)
    httpd.serve_forever()


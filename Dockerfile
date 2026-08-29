# Start from a small, official Python image instead of a full OS image.
# Smaller image = faster builds/pushes/pulls later in the pipeline.
FROM python:3.12-slim

# All commands below run from /app inside the container.
WORKDIR /app

# Copy ONLY the dependency list first (not the whole app yet).
# Docker caches each layer - if requirements.txt hasn't changed, this
# install step is skipped on the next build, which speeds things up a lot.
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Now copy the actual application code. This layer changes often, so we
# keep it last - it's the only layer that has to rebuild on most edits.
COPY app/main.py .

# Just documentation for humans/tools - doesn't actually open the port.
EXPOSE 8000

# The command that runs when the container starts: launch the FastAPI app
# with uvicorn, listening on all interfaces so it's reachable from outside
# the container.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

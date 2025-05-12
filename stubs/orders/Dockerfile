# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set environment variables
# Prevents Python from writing pyc files to disc (equivalent to python -B)
ENV PYTHONDONTWRITEBYTECODE 1
# Prevents Python from buffering stdout and stderr (important for logging in Docker)
ENV PYTHONUNBUFFERED 1

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file into the container at /app
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container at /app
COPY orders_service_stub.py .

# Expose the port the app runs on (Cloud Run will set the PORT env var)
EXPOSE 5001

# Define the command to run your app using Gunicorn
# Cloud Run sets the PORT environment variable, which Gunicorn will use.
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "orders_service_stub:app"]
from flask import Flask, request, jsonify, redirect
import psycopg2
import os
import random
import string

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )


@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/shorten", methods=["POST"])
def shorten():
    data = request.get_json()

    if not data or "url" not in data:
        return jsonify({"error": "url is required"}), 400

    original_url = data["url"]

    shortcode = ''.join(
        random.choices(
            string.ascii_letters + string.digits,
            k=6
        )
    )

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO urls (shortcode, original_url)
        VALUES (%s, %s)
        """,
        (shortcode, original_url)
    )

    conn.commit()

    cur.close()
    conn.close()

    return jsonify(
        {
            "shortcode": shortcode
        }
    ), 201


@app.route("/<shortcode>")
def redirect_url(shortcode):

    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT original_url
        FROM urls
        WHERE shortcode = %s
        """,
        (shortcode,)
    )

    result = cur.fetchone()

    cur.close()
    conn.close()

    if result:
        return redirect(result[0])

    return jsonify(
        {
            "error": "not found"
        }
    ), 404


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=8080
    )

async function postData(url = '/api/endpoint') {
	try {
		const response = await fetch(url, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json'
			},
			body: JSON.stringify({ request: "counter" }) // Ensure JSON is properly formatted
		});

		const result = await response.json(); // Ensure we wait for JSON parsing

		// Fix the potential "undefined" issue in innerText
		document.getElementById("result").innerText = result?.counter !== undefined
			? "Here is a number from the server: " + result.counter
			: "Could not get the number";

	} catch (error) {
		console.error("Error:", error);
		document.getElementById("result").innerText = "Request failed";
	}
}
// Attach event listener to button
document.getElementById("postButton").addEventListener("click", () => {
	postData();
});

console.log("Script loaded");


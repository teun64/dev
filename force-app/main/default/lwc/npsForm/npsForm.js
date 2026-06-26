import { LightningElement, api } from 'lwc';

export default class NpsForm extends LightningElement {
    @api defaultScore; // Input variable to default the score selection from Flow
    @api selectedScore; // Output variable for Flow to capture the user's selected score

    // Score options from 0 to 10
    scoreOptions = Array.from({ length: 11 }, (_, i) => ({
        label: i.toString(),
        value: i.toString(),
    }));

    connectedCallback() {
        // Initialize selectedScore with defaultScore if it is defined (even if it's 0)
        this.selectedScore = this.defaultScore !== undefined && this.defaultScore !== null 
            ? this.defaultScore.toString() 
            : null;
    }

    // Define colors based on the provided HTML colors
    colorMap = [
        "#E57373", "#EF5350", "#F06292", "#BA68C8", "#7986CB", 
        "#64B5F6", "#4DB6AC", "#81C784", "#AED581", "#DCE775",
        "#D4E157"
    ];

    // Getter to apply dynamic styles to each score option
    get scoreStyles() {
        return this.scoreOptions.map((option, index) => ({
            ...option,
            style: `
                display: inline-block;
                padding: 10px;
                width: 80px;
                text-align: center;
                font-size: 18px;
                font-weight: bold;
                background-color: ${this.colorMap[index]};
                color: white;
                border: ${this.selectedScore === option.value ? '2px solid #444' : 'none'};
                cursor: pointer;
            `,
        }));
    }

    handleScoreClick(event) {
        this.selectedScore = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('scorechange', { detail: this.selectedScore }));
    }
}